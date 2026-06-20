extends CharacterBody2D
## Enemy — 적 한 마리. mino1 play.js 의 enemyGroup 스프라이트 + _edata 에 해당.
## AI(추격·돌진·매복·치고빠지기)·의사 애니·근접 접촉 피해·피격/사망을 담는다.
## 밸런스 숫자(hp·dmg·xp·속도·배율)는 mino1 값을 그대로 보존한다.
##
## Main 이 spawn 시 setup() 으로 스탯·플레이어 참조를 넣어준다.
## 플레이어 피해는 player.hurt() 로, FX(데미지숫자·파티클·사망)는 main 콜백으로 보낸다.

const AI_ENEMY_H := 70.0      # 적 표시 높이(px) — mino1 104 를 minho2 주인공 88 비율로 축소(104/132*88)
const PERSP_SQUASH := 0.92    # 미세 원근 (Player 와 동일)

@onready var sprite: Sprite2D = $Sprite
@onready var shadow: Sprite2D = $Shadow

# ── 적 스탯 (mino1 _edata) ─────────────────────────────────
var etype := "slime"          # 적 종류 키 (ENEMY_DEFS)
var hp := 39.0
var maxhp := 39.0
var sp := 80.0                 # 이동 속도
var dmg := 5.0
var xp := 10
var gold_base := 3
var is_elite := false

# ── AI / 타이머 상태 (mino1 _edata) ────────────────────────
var ai_state := "idle"        # boar: idle|windup|dash|recover / croc: idle|alert|lunge / crow: idle|approach|strike|flee / toad: idle|shooting
var ai_t := 0.0
var hit_cd := 0.0             # 접촉 피해 쿨다운 (적 → 플레이어)
var atk_cd := 0.0            # 공격 쿨다운
var slow_t := 0.0            # 독 둔화 남은 시간 (S5 독장판용 — 지금은 0)
var charge_dx := 0.0
var charge_dy := 0.0

# ── 의사 애니 상태 ─────────────────────────────────────────
var anim_t := 0.0
var atk_lunge_t := 0.0
var atk_lunge_vx := 0.0
var atk_lunge_vy := 0.0
var base_scale := Vector2.ONE  # 엘리트 배율 + 원근 반영 후 기본 스케일
var flash_t := 0.0            # 흰색 피격 플래시 타이머
var shadow_lift := 0.0

var dead := false             # 사망 처리 완료 플래그

# 외부 참조 (Main 이 setup 으로 넣어줌)
var player: Node = null       # Player 노드 (위치·hurt)
var main: Node = null          # Main (FX·사망 콜백)

var elite_label: Label = null
var hit_tween: Tween = null


# ── Main 이 스폰 후 호출: 스탯·참조 주입 ───────────────────
func setup(type_key: String, stats: Dictionary, p_player: Node, p_main: Node) -> void:
	etype = type_key
	hp = stats["hp"]
	maxhp = stats["maxhp"]
	sp = stats["sp"]
	dmg = stats["dmg"]
	xp = int(stats["xp"])
	gold_base = int(stats["gold_base"])
	is_elite = stats["is_elite"]
	player = p_player
	main = p_main
	# toad 는 시작 공격 쿨다운 랜덤 (mino1)
	if etype == "toad":
		atk_cd = 1.0 + randf() * 0.8


func _ready() -> void:
	_setup_sprite()
	_setup_shadow()


func _setup_sprite() -> void:
	var def: Dictionary = GameData.ENEMY_DEFS.get(etype, {})
	var sprite_key: String = def.get("sprite", "slime")
	var tex := _load_tex("res://assets/sprites/%s.png" % sprite_key)
	if tex:
		sprite.texture = tex
		var h := float(tex.get_height())
		var s := AI_ENEMY_H / h if h > 0.0 else 1.0
		# 엘리트: 1.6배 크게 (mino1)
		if is_elite:
			s *= 1.6
		sprite.scale = Vector2(s, s * PERSP_SQUASH)
		base_scale = sprite.scale
		if is_elite:
			sprite.modulate = Color8(0xff, 0xcc, 0x22)   # 금색 틴트
	else:
		var ph := ColorRect.new()
		ph.size = Vector2(34, 50)
		ph.position = Vector2(-17, -50)
		ph.color = Color(0.8, 0.4, 0.4)
		add_child(ph)
		base_scale = Vector2.ONE

	# 엘리트 이름표 (월드 좌표에 붙는 라벨)
	if is_elite:
		elite_label = Label.new()
		if main and main.has_method("get_kfont") and main.get_kfont():
			elite_label.add_theme_font_override("font", main.get_kfont())
		elite_label.add_theme_font_size_override("font_size", 16)
		elite_label.add_theme_color_override("font_color", Color8(0xff, 0xdd, 0x44))
		elite_label.add_theme_color_override("font_outline_color", Color8(0x4a, 0x2a, 0x00))
		elite_label.add_theme_constant_override("outline_size", 4)
		elite_label.text = "★ 엘리트"
		elite_label.position = Vector2(-30, -AI_ENEMY_H * 1.5)
		elite_label.z_index = 200
		add_child(elite_label)


func _setup_shadow() -> void:
	var w := AI_ENEMY_H * (0.62 if is_elite else 0.42)
	shadow.texture = _make_shadow_tex(int(w), int(w * 0.34))
	shadow.modulate = Color(0, 0, 0, 0.26)
	shadow.position = Vector2(0, 2)


# ════════════════════════════════════════════════════════════
#  매 프레임: AI + 의사 애니 + 그림자 + depth
# ════════════════════════════════════════════════════════════
func _physics_process(delta: float) -> void:
	if dead or player == null:
		return

	# 히트스톱 중에는 적도 멈춘다 (Main 이 시간배율로 알림)
	var ts: float = main.time_scale if main else 1.0
	var dt := delta * ts

	# 타이머 감소
	if flash_t > 0.0:
		flash_t -= dt
		if flash_t <= 0.0 and not is_elite:
			sprite.modulate = Color.WHITE
		elif flash_t <= 0.0 and is_elite:
			sprite.modulate = Color8(0xff, 0xcc, 0x22)
	if hit_cd > 0.0:
		hit_cd = maxf(0.0, hit_cd - dt)
	if atk_cd > 0.0:
		atk_cd = maxf(0.0, atk_cd - dt)
	if slow_t > 0.0:
		slow_t = maxf(0.0, slow_t - dt)
	ai_t += dt

	if hp <= 0.0:
		_die()
		return

	var ppos: Vector2 = player.global_position
	var ddx := ppos.x - global_position.x
	var ddy := ppos.y - global_position.y
	var dist := sqrt(ddx * ddx + ddy * ddy)
	if dist < 1.0:
		dist = 1.0

	var speed_mult := 0.7 if slow_t > 0.0 else 1.0
	# 접촉 거리 (mino1: AI_ENEMY_H*0.5 + AI_HERO_H*0.35)
	var touch_dist := AI_ENEMY_H * 0.5 + Player.AI_HERO_H * 0.35

	var dir := Vector2(ddx / dist, ddy / dist)

	# ── type 별 AI 분기 (mino1 _updateEnemies 1:1) ──────────
	match etype:
		"boar":
			_ai_boar(dt, dist, dir, touch_dist, speed_mult)
		"toad":
			_ai_toad(dt, dist, dir, touch_dist, speed_mult)
		"crow":
			_ai_crow(dt, dist, dir, touch_dist, speed_mult)
		"croc":
			_ai_croc(dt, dist, dir, touch_dist, speed_mult)
		"hedgehog":
			_ai_basic(dt, dist, dir, touch_dist, speed_mult, 0.8, 0.6)
		_:
			# slime, rat, pig, wolf
			_ai_basic(dt, dist, dir, touch_dist, speed_mult, 0.8, 0.6)

	move_and_slide()
	# 월드 경계 안에 가둔다
	global_position.x = clampf(global_position.x, 40.0, GameData.WORLD_W - 40.0)
	global_position.y = clampf(global_position.y, 40.0, GameData.WORLD_H - 40.0)

	# depth = y (mino1 setDepth(e.y))
	z_index = int(global_position.y)

	# 좌우 반전 (이동 방향 기준)
	if absf(velocity.x) > 1.0:
		sprite.flip_h = velocity.x < 0.0
	elif absf(ddx) > 1.0:
		sprite.flip_h = ddx < 0.0

	_apply_anim(dt, dist)


# ── 기본 추격 (slime, rat, pig, wolf, hedgehog) ─────────────
func _ai_basic(dt: float, dist: float, dir: Vector2, touch_dist: float, sm: float, cd: float, inv: float) -> void:
	velocity = dir * sp * sm
	if dist < touch_dist and hit_cd <= 0.0 and not _player_invincible():
		hit_cd = cd
		_deal_contact(dmg, inv, dir)


# ── boar (멧돼지): 돌진형 ──────────────────────────────────
func _ai_boar(dt: float, dist: float, dir: Vector2, touch_dist: float, sm: float) -> void:
	if ai_state == "idle":
		if dist < 260.0 and atk_cd <= 0.0:
			ai_state = "windup"
			ai_t = 0.0
			charge_dx = dir.x
			charge_dy = dir.y
			velocity = Vector2.ZERO
		else:
			velocity = dir * sp * sm
	elif ai_state == "windup":
		velocity = Vector2.ZERO
		var shake := sin(ai_t * 60.0) * 3.0
		global_position.x += shake * dt * 8.0
		sprite.modulate = Color8(0xff, 0x44, 0x44)
		if main:
			main.draw_telegraph_dash(global_position, Vector2(charge_dx, charge_dy), minf(1.0, ai_t / 0.6))
		if ai_t >= 0.6:
			ai_state = "dash"
			ai_t = 0.0
			sprite.modulate = Color8(0xff, 0xcc, 0x22) if is_elite else Color.WHITE
	elif ai_state == "dash":
		velocity = Vector2(charge_dx, charge_dy) * sp * 3.0
		if dist < touch_dist and hit_cd <= 0.0 and not _player_invincible():
			hit_cd = 0.9
			_deal_contact(dmg * 1.5, 0.7, Vector2(charge_dx, charge_dy))
		if ai_t >= 0.4:
			ai_state = "recover"
			ai_t = 0.0
			velocity = Vector2.ZERO
	elif ai_state == "recover":
		velocity = Vector2.ZERO
		if ai_t >= 0.6:
			ai_state = "idle"
			atk_cd = 1.4
			ai_t = 0.0


# ── toad (독두꺼비): 원거리 독침 (S1엔 투사체 대신 근접만; 투사체는 S3) ──
# mino1 은 독침 투사체를 쏘지만, 투사체 시스템은 아직 없으므로
# 사거리 접근 + 근접 접촉 피해만 보존하고 발사는 S3에서 붙인다.
func _ai_toad(dt: float, dist: float, dir: Vector2, touch_dist: float, sm: float) -> void:
	var fire_range := 260.0
	if dist > fire_range * 0.8:
		velocity = dir * sp * 0.7 * sm
	else:
		velocity = Vector2.ZERO
	if dist < touch_dist and hit_cd <= 0.0 and not _player_invincible():
		hit_cd = 0.9
		_deal_contact(dmg * 0.6, 0.5, dir)


# ── crow (까마귀): 치고 빠지기 ─────────────────────────────
func _ai_crow(dt: float, dist: float, dir: Vector2, touch_dist: float, sm: float) -> void:
	if ai_state == "idle":
		if dist < 220.0:
			ai_state = "approach"
			ai_t = 0.0
		velocity = dir * sp * sm
	elif ai_state == "approach":
		velocity = dir * sp * 1.25 * sm
		if dist < touch_dist + 10.0:
			ai_state = "strike"
			ai_t = 0.0
	elif ai_state == "strike":
		if hit_cd <= 0.0 and not _player_invincible():
			hit_cd = 0.6
			_deal_contact(dmg, 0.5, dir)
		ai_state = "flee"
		ai_t = 0.0
		atk_cd = 1.6
		charge_dx = -dir.x
		charge_dy = -dir.y
	elif ai_state == "flee":
		velocity = Vector2(charge_dx, charge_dy) * sp * 0.95 * sm
		if ai_t >= 0.35 or dist > 150.0:
			ai_state = "idle"
			ai_t = 0.0


# ── croc (악어): 매복형 ────────────────────────────────────
func _ai_croc(dt: float, dist: float, dir: Vector2, touch_dist: float, sm: float) -> void:
	if ai_state == "idle":
		velocity = dir * sp * 0.5 * sm
		if dist < 180.0 and atk_cd <= 0.0:
			ai_state = "alert"
			ai_t = 0.0
			velocity = Vector2.ZERO
			charge_dx = dir.x
			charge_dy = dir.y
	elif ai_state == "alert":
		velocity = Vector2.ZERO
		var pulse := 0.5 + 0.5 * sin(ai_t * 18.0)
		var prog := minf(1.0, ai_t / 0.7)
		if main:
			main.draw_telegraph_circle(global_position, 20.0 + 40.0 * prog, pulse * prog)
		sprite.modulate = Color8(0xff, 0x55, 0x00)
		if ai_t >= 0.7:
			ai_state = "lunge"
			ai_t = 0.0
			sprite.modulate = Color8(0xff, 0xcc, 0x22) if is_elite else Color.WHITE
	elif ai_state == "lunge":
		velocity = Vector2(charge_dx, charge_dy) * sp * 3.5
		if dist < touch_dist and hit_cd <= 0.0 and not _player_invincible():
			hit_cd = 1.0
			_deal_contact(dmg * 1.8, 0.8, Vector2(charge_dx, charge_dy))
		if ai_t >= 0.28:
			ai_state = "idle"
			atk_cd = 2.2
			ai_t = 0.0


# ── 플레이어에게 접촉 피해 + 공격 룽지 트리거 ───────────────
func _deal_contact(raw_dmg: float, inv: float, dir: Vector2) -> void:
	if player and player.has_method("hurt"):
		player.hurt(raw_dmg, inv)
	atk_lunge_t = 0.18
	atk_lunge_vx = dir.x
	atk_lunge_vy = dir.y


func _player_invincible() -> bool:
	if player and player.has_method("is_invincible"):
		return player.is_invincible()
	return false


# ════════════════════════════════════════════════════════════
#  피격 — Main 의 전투 판정이 호출 (데미지·플래시·넉백·찌그러짐)
# ════════════════════════════════════════════════════════════
func take_hit(amount: float, is_crit: bool, from_pos: Vector2) -> void:
	if dead:
		return
	hp -= amount
	flash_t = 0.22 if is_crit else 0.15
	sprite.modulate = Color.WHITE

	# 넉백: 공격 방향(주인공→적)으로 임펄스 (mino1 nkSpd 170/260)
	var nk_dir := (global_position - from_pos)
	if nk_dir.length() < 0.5:
		nk_dir = Vector2.RIGHT
	nk_dir = nk_dir.normalized()
	var nk_spd := 260.0 if is_crit else 170.0
	velocity += nk_dir * nk_spd

	# 찌그러짐: 납작→홀쭉→복원 (mino1 Tween 의사 애니)
	_hit_squash()


func _hit_squash() -> void:
	if hit_tween and hit_tween.is_valid():
		hit_tween.kill()
	var bs := base_scale
	sprite.scale = Vector2(bs.x * 1.35, bs.y * 0.72)   # 납작
	hit_tween = create_tween()
	hit_tween.tween_interval(0.06)
	hit_tween.tween_callback(func(): sprite.scale = Vector2(bs.x * 0.82, bs.y * 1.22))  # 홀쭉
	hit_tween.tween_interval(0.055)
	hit_tween.tween_callback(func(): sprite.scale = bs)  # 복원 (이후 애니가 다시 적용)


# ════════════════════════════════════════════════════════════
#  사망 — 파티클·골드·XP·드랍을 Main 에 알리고 자기 자신 제거
# ════════════════════════════════════════════════════════════
func _die() -> void:
	if dead:
		return
	dead = true
	var pos := global_position
	# 충돌·AI 정지
	set_physics_process(false)
	if has_node("CollisionShape2D"):
		$CollisionShape2D.set_deferred("disabled", true)
	if elite_label:
		elite_label.queue_free()
		elite_label = null

	# 사망 연출: 잠깐 확대 + 흰 플래시 → 펑 (mino1)
	sprite.modulate = Color.WHITE
	sprite.rotation = 0.0
	var bs := base_scale
	sprite.scale = Vector2(bs.x * 1.4, bs.y * 1.4)

	# Main 에 사망 보상(XP·골드·파티클·드랍) 위임
	if main and main.has_method("on_enemy_died"):
		main.on_enemy_died(self, pos)

	# 60ms 후 임팩트 원 + 소멸
	var tw := create_tween()
	tw.tween_interval(0.06)
	tw.tween_callback(func():
		if main and main.has_method("spawn_impact"):
			var ir := 72.0 if is_elite else 48.0
			main.spawn_impact(pos, ir, Color(1, 1, 1, 1))
		queue_free()
	)


# ════════════════════════════════════════════════════════════
#  의사 애니메이션 (mino1 _applyEnemyAnim 1:1 — scale/rotation)
# ════════════════════════════════════════════════════════════
func _apply_anim(dt: float, dist: float) -> void:
	# 피격 squash tween 이 도는 동안엔 애니가 덮어쓰지 않게 양보
	if hit_tween and hit_tween.is_valid():
		return
	var bs := base_scale
	anim_t += dt
	var vel := velocity.length()
	var moving := vel > 12.0

	# 그림자 lift (이동 중 sin)
	if moving:
		var amp := 3.0
		var freq := 8.0
		if etype in ["slime", "toad", "rat"]:
			amp = 7.0; freq = 10.0
		elif etype == "crow":
			amp = 5.0; freq = 9.0
		shadow_lift = absf(sin(anim_t * freq)) * amp
	else:
		shadow_lift = 0.0
	_sync_shadow()

	# 공격 룽지 감소
	if atk_lunge_t > 0.0:
		atk_lunge_t -= dt

	# 공격 룽지 중: 앞으로 기울임 + 늘어남 (mino1)
	if atk_lunge_t > 0.0:
		var lp := atk_lunge_t / 0.20
		var tilt_sign := 1.0 if atk_lunge_vx >= 0.0 else -1.0
		sprite.rotation = tilt_sign * 0.30 * lp
		sprite.scale = Vector2(bs.x * (1.0 + 0.18 * lp), bs.y * (1.0 - 0.12 * lp))
		return

	var t := anim_t
	match etype:
		"slime", "toad":
			if moving:
				var phase := sin(t * 10.0)
				var sq_y := 1.0 + (-0.18 * phase if phase > 0.0 else 0.14 * absf(phase))
				var sq_x := 2.0 - sq_y
				sprite.scale = Vector2(bs.x * sq_x, bs.y * sq_y)
				sprite.rotation = 0.0
			else:
				var breathe := 1.0 + sin(t * 1.6) * 0.04
				sprite.scale = Vector2(bs.x * breathe, bs.y / breathe)
				sprite.rotation = 0.0
		"crow":
			if moving:
				var flap := 1.0 + sin(t * 18.0) * 0.20
				sprite.scale = Vector2(bs.x, bs.y * flap)
				sprite.rotation = sin(t * 9.0) * 0.08
			else:
				var idle_flap := 1.0 + sin(t * 4.0) * 0.06
				sprite.scale = Vector2(bs.x, bs.y * idle_flap)
				sprite.rotation = 0.0
		"pig", "boar":
			if moving:
				sprite.rotation = sin(t * 9.0) * 0.10
				sprite.scale = bs
			else:
				sprite.rotation = sin(t * 2.5) * 0.04
				sprite.scale = Vector2(bs.x * (1.0 + sin(t * 1.8) * 0.03), bs.y)
		"wolf":
			if moving:
				var stretch := 1.0 + absf(sin(t * 10.0)) * 0.12
				sprite.scale = Vector2(bs.x * stretch, bs.y * (2.0 - stretch))
				sprite.rotation = sin(t * 10.0) * 0.06
			else:
				sprite.scale = Vector2(bs.x * (1.0 + sin(t * 1.8) * 0.03), bs.y)
				sprite.rotation = 0.0
		"rat":
			if moving:
				var hop := 1.0 + absf(sin(t * 16.0)) * 0.12
				sprite.scale = Vector2(bs.x * (2.0 - hop), bs.y * hop)
				sprite.rotation = sin(t * 16.0) * 0.07
			else:
				sprite.scale = Vector2(bs.x, bs.y * (1.0 + sin(t * 3.0) * 0.05))
				sprite.rotation = 0.0
		"hedgehog", "croc":
			if moving:
				sprite.scale = Vector2(bs.x * (1.0 + sin(t * 6.0) * 0.05), bs.y * (1.0 - sin(t * 6.0) * 0.03))
			else:
				var breathe2 := 1.0 + sin(t * 1.2) * 0.03
				sprite.scale = Vector2(bs.x * breathe2, bs.y)
			sprite.rotation = 0.0
		_:
			if moving:
				var hop2 := 1.0 + absf(sin(t * 8.0)) * 0.08
				sprite.scale = Vector2(bs.x, bs.y * hop2)
				sprite.rotation = sin(t * 8.0) * 0.05
			else:
				sprite.scale = Vector2(bs.x * (1.0 + sin(t * 1.5) * 0.03), bs.y)
				sprite.rotation = 0.0


# 그림자: lift 만큼 작아지고 옅어짐 (mino1 _syncShadow, 클래시로얄식)
func _sync_shadow() -> void:
	var lift_n := minf(1.0, shadow_lift / 18.0)
	var shrink := 1.0 - lift_n * 0.35
	shadow.scale = Vector2(shrink, shrink)
	shadow.modulate.a = 0.26 * (1.0 - lift_n * 0.45)


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _make_shadow_tex(w: int, h: int) -> ImageTexture:
	w = maxi(8, w)
	h = maxi(4, h)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := w / 2.0
	var cy := h / 2.0
	for y in h:
		for x in w:
			var dx := (x - cx) / cx
			var dy := (y - cy) / cy
			var d := dx * dx + dy * dy
			if d <= 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 1.0 - d * 0.6))
	return ImageTexture.create_from_image(img)
