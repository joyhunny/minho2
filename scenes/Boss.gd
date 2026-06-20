extends CharacterBody2D
class_name Boss
## Boss — 지역 보스 한 마리. mino1 play.js 의 _spawnBoss 계열 + _updateBoss 패턴 1:1 대응.
## 4종: boar_king(우두머리 멧돼지)·croc(심연의 악어)·wolf_king(우두머리 늑대)·elephant(오염의 군주).
## 밸런스 숫자(HP·atkInterval·돌진 속도·피해·메테오 개수·독장판)는 mino1 값을 그대로 보존한다.
##
## "옮기며 업그레이드": 등장 연출(포효 대신 화면 흔들림+붉은 섬광)·찌그러짐 Tween·
## 돌진 예고선·기절 별·메테오 예고원·HP 잔상바 + 카메라 흔들림으로 타격감 보강.
##
## Main 이 setup() 으로 타입·플레이어·main 참조를 주입한다. 보스 피격은 Main._update_combat 이,
## 보스 패턴(이동·돌진·메테오·독)은 이 노드의 _physics_process 가 처리한다.

const PERSP_SQUASH := 0.92

# 보스 종류별 표시 높이(px). mino1 fitH 값을 minho2 비율(/132*88 ≈ 0.667)로 축소.
const BOSS_H := {
	"boar_king": 134.0,   # mino1 200
	"croc":      140.0,   # mino1 210
	"wolf_king": 131.0,   # mino1 196
	"elephant":  192.0,   # mino1 288 (최종보스 위엄)
}
const BOSS_SPRITE := {
	"boar_king": "boar", "croc": "croc", "wolf_king": "wolf", "elephant": "boss_elephant",
}
const BOSS_TINT := {
	"boar_king": Color8(0xc9, 0x8a, 0x4a),  # 흙갈색
	"croc":      Color8(0x33, 0xdd, 0x66),  # 독성 초록
	"wolf_king": Color8(0xbf, 0xc4, 0xcc),  # 잿빛
	"elephant":  Color.WHITE,
}
const BOSS_LABEL := {
	"boar_king": "🐗 우두머리 멧돼지 — 들판의 폭군",
	"croc":      "☠ 심연의 악어 — 늪의 지배자",
	"wolf_king": "🐺 우두머리 늑대 — 폐허의 사냥꾼",
	"elephant":  "💀 코끼리 — 오염의 군주",
}
const BOSS_WARN := {
	"boar_king": ["⚠ 우두머리 멧돼지 등장!", Color8(0xff, 0xaa, 0x55)],
	"croc":      ["⚠ 심연의 악어 — 늪의 지배자 등장!", Color8(0x44, 0xff, 0x88)],
	"wolf_king": ["⚠ 우두머리 늑대 등장!", Color8(0xcc, 0xcc, 0xcc)],
	"elephant":  ["⚠ 코끼리 보스 등장!", Color8(0xff, 0x44, 0x44)],
}

@onready var sprite: Sprite2D = $Sprite
@onready var shadow: Sprite2D = $Shadow

var boss_type := "elephant"
var hp := 600.0
var maxhp := 600.0
var atk_timer := 0.0
var atk_interval := 3.0
var state := "intro"         # intro → chase (그 뒤 패턴별 dash_state)
var intro_t := 0.0
var intro_fx_done := false
var walk_t := 0.0
var base_scale := Vector2.ONE
var dead := false

# 돌진/기절 상태 (boar_king·wolf_king·croc 공통)
var dash_state := "idle"     # idle|windup|dash|stunned|recover
var dash_t := 0.0
var dash_dir := Vector2.ZERO
var vulnerable := false       # 기절·빈틈 = 약점 (Main 피격이 배수 적용)
var vuln_mult := 1.6
var stun_t := 0.0
var stun_dur := 0.0
var recover_t := 0.0
var recover_dur := 0.0
var tel_color := Color8(0xff, 0xaa, 0x55)

# 악어 독 장판 (mino1 _crocBossPoisons)
var poison_timer := 0.0
var poison_interval := 4.0
var poisons: Array = []       # [{x, y, t, life}]

var player: Node = null
var main: Node = null
var hit_tween: Tween = null

# HP 바 (화면 고정 CanvasLayer) + 패턴 그리기(월드 좌표 child Node2D)
var _hp_layer: CanvasLayer = null
var _hp_draw: Node2D = null
var _hp_label: Label = null
var _hp_pct_label: Label = null
var _hp_trail := 0.0
var _pattern_draw: Node2D = null   # 예고선·기절별·독장판·메테오를 월드에 그림

# 메테오 (elephant 궁극기) — Main 의 메테오와 별개로 보스 자체 메테오
var meteors: Array = []        # [{tx, ty, warn_t, falling, fall_y, hit, hit_t}]


func setup(type_key: String, chapter: int, p_player: Node, p_main: Node) -> void:
	boss_type = type_key
	player = p_player
	main = p_main
	# 보스별 기본 HP·공격 간격 (mino1 그대로)
	var base_hp := 600.0
	match boss_type:
		"boar_king":
			base_hp = 440.0
			atk_interval = maxf(1.8, 3.0 - (chapter - 1) * 0.15)
			tel_color = Color8(0xff, 0xaa, 0x55)
		"wolf_king":
			base_hp = 480.0
			atk_interval = maxf(1.3, 2.2 - (chapter - 1) * 0.12)
			tel_color = Color8(0xdd, 0xdd, 0xdd)
		"croc":
			base_hp = 520.0
			atk_interval = maxf(1.5, 2.8 - (chapter - 1) * 0.15)
		_:  # elephant
			base_hp = 600.0
			atk_interval = maxf(2.0, 3.5 - (chapter - 1) * 0.2)
	maxhp = round(base_hp * pow(1.25, chapter - 1))
	hp = maxhp
	_hp_trail = maxhp


func _ready() -> void:
	_setup_sprite()
	_setup_shadow()
	_setup_hp_bar()
	_setup_pattern_draw()
	# 등장 경고 텍스트 (잠깐 떴다 사라짐)
	_show_warn()


func _setup_sprite() -> void:
	var sprite_key: String = BOSS_SPRITE.get(boss_type, "boss_elephant")
	var tex := _load_tex("res://assets/sprites/%s.png" % sprite_key)
	if tex:
		sprite.texture = tex
		var h := float(tex.get_height())
		var target: float = BOSS_H.get(boss_type, 160.0)
		var s := target / h if h > 0.0 else 1.0
		sprite.scale = Vector2(s, s * PERSP_SQUASH)
		base_scale = sprite.scale
		sprite.modulate = BOSS_TINT.get(boss_type, Color.WHITE)
	else:
		var ph := ColorRect.new()
		ph.size = Vector2(80, 110)
		ph.position = Vector2(-40, -110)
		ph.color = Color(0.6, 0.2, 0.2)
		add_child(ph)
		base_scale = Vector2.ONE


func _setup_shadow() -> void:
	var target: float = BOSS_H.get(boss_type, 160.0)
	var w := target * 0.7
	shadow.texture = _make_shadow_tex(int(w), int(w * 0.32))
	shadow.modulate = Color(0, 0, 0, 0.32)
	shadow.position = Vector2(0, 4)


func _setup_hp_bar() -> void:
	_hp_layer = CanvasLayer.new()
	_hp_layer.name = "BossHpLayer"
	_hp_layer.layer = 9   # HUD(5)·info(6)·flash(7)·stat(8) 위
	add_child(_hp_layer)

	_hp_draw = Node2D.new()
	_hp_draw.set_script(_make_hp_draw_script())
	_hp_draw.set("boss", self)
	_hp_layer.add_child(_hp_draw)

	_hp_label = _mk_label(str(BOSS_LABEL.get(boss_type, "보스")), 15, Color8(0xff, 0xaa, 0xaa))
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_layer.add_child(_hp_label)
	_hp_pct_label = _mk_label("", 12, Color.WHITE)
	_hp_pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_layer.add_child(_hp_pct_label)


func _setup_pattern_draw() -> void:
	# 예고선·기절별·독장판·메테오를 월드 좌표로 그릴 child (보스보다 위로)
	_pattern_draw = Node2D.new()
	_pattern_draw.set_script(_make_pattern_script())
	_pattern_draw.set("boss", self)
	_pattern_draw.z_index = 3100   # Fx(3000) 위
	# 보스의 자식이 아니라 Main 의 자식으로 — 보스가 움직여도 월드 절대좌표 유지
	if main:
		main.add_child(_pattern_draw)
	else:
		add_child(_pattern_draw)


# ════════════════════════════════════════════════════════════
#  매 프레임 패턴 (mino1 _updateBoss 1:1)
# ════════════════════════════════════════════════════════════
func _physics_process(delta: float) -> void:
	if dead or player == null or main == null:
		return
	var ts: float = main.time_scale
	var dt := delta * ts

	z_index = int(global_position.y) + 1000

	# ── 인트로: 등장 연출(흔들림+섬광) 한 번 + 1.8초 대기 ──
	if state == "intro":
		if not intro_fx_done:
			intro_fx_done = true
			main.add_shake(0.5, 10.0)
			Audio.roar()   # 보스 포효 (mino1 MinoSound.roar)
			if main.skills:
				main.skills.trigger_flash(Color8(0xff, 0x66, 0x44), 0.30)
		intro_t += dt
		_walk_anim(dt, false)
		if intro_t >= 1.8:
			state = "chase"
		_update_hp_trail(dt)
		return

	var p: Dictionary = GameState.player
	var to_p: Vector2 = player.global_position - global_position
	var dist := maxf(1.0, to_p.length())
	var dir: Vector2 = to_p / dist
	sprite.flip_h = to_p.x < 0.0

	match boss_type:
		"croc":
			_pattern_croc(dt, dist, dir, p)
		"boar_king", "wolf_king":
			_pattern_charger(dt, dist, dir, p)
		_:
			_pattern_elephant(dt, dist, dir, p)

	move_and_slide()
	global_position.x = clampf(global_position.x, 60.0, GameData.WORLD_W - 60.0)
	global_position.y = clampf(global_position.y, 60.0, GameData.WORLD_H - 60.0)

	var moving := velocity.length() > 12.0
	_walk_anim(dt, moving)
	_update_hp_trail(dt)
	_update_meteors(dt, p)

	if hp <= 0.0:
		_die()


# ── 심연의 악어: 빠른 돌진 + 독 장판 (mino1) ──────────────────
func _pattern_croc(dt: float, dist: float, dir: Vector2, p: Dictionary) -> void:
	atk_timer += dt
	if dash_state == "idle":
		velocity = dir * 55.0 if dist > 120.0 else Vector2.ZERO
		if atk_timer >= atk_interval:
			atk_timer = 0.0
			dash_state = "windup"
			dash_t = 0.0
			dash_dir = dir
			sprite.modulate = Color8(0x88, 0xff, 0x44)
	elif dash_state == "windup":
		dash_t += dt
		velocity = Vector2.ZERO
		main.fx.telegraphs.append({"kind": "boss_line", "pos": global_position,
			"dir": dash_dir, "len": 280.0, "color": Color(0.27, 1.0, 0.53),
			"alpha": 0.8 * minf(1.0, dash_t / 0.5)})
		if dash_t >= 0.5:
			dash_state = "dash"
			dash_t = 0.0
			sprite.modulate = BOSS_TINT["croc"]
	elif dash_state == "dash":
		dash_t += dt
		velocity = dash_dir * 380.0
		if dist < 110.0 and not player.is_invincible():
			main.hazard_damage(22.0, 0.9, Color.WHITE, "")
		if dash_t >= 0.35:
			dash_state = "idle"
			dash_t = 0.0
			velocity = Vector2.ZERO

	# 패턴2: 독 장판 3개 부채꼴 (4초마다)
	poison_timer += dt
	if poison_timer >= poison_interval:
		poison_timer = 0.0
		var base_ang := dir.angle()
		for i in 3:
			var ang := base_ang + (i - 1) * 0.6
			poisons.append({"x": global_position.x + cos(ang) * 80.0,
				"y": global_position.y + sin(ang) * 80.0, "t": 0.0, "life": 5.0})

	# 독 장판 갱신 + 피해 (초당 1회)
	for i in range(poisons.size() - 1, -1, -1):
		var po: Dictionary = poisons[i]
		var prev_t: float = po["t"]
		po["t"] = prev_t + dt
		if po["t"] >= po["life"]:
			poisons.remove_at(i)
			continue
		if floor(po["t"]) != floor(prev_t) and not player.is_invincible():
			if Vector2(p["x"] - po["x"], p["y"] - po["y"]).length() < 44.0:
				main.hazard_damage(8.0, 0.0, Color8(0x44, 0xff, 0x44), "")


# ── 우두머리 멧돼지/늑대: 돌진 → (피하면) 빈틈 / (바위에 박으면) 기절 ──
func _pattern_charger(dt: float, dist: float, dir: Vector2, p: Dictionary) -> void:
	atk_timer += dt
	var chase_sp := 95.0 if boss_type == "wolf_king" else 60.0
	if dash_state == "idle":
		vulnerable = false
		velocity = dir * chase_sp if dist > 110.0 else Vector2.ZERO
		if atk_timer >= atk_interval:
			atk_timer = 0.0
			dash_state = "windup"
			dash_t = 0.0
			dash_dir = dir
	elif dash_state == "windup":
		dash_t += dt
		velocity = Vector2.ZERO
		var tw := 0.6 + 0.4 * absf(sin(dash_t * 18.0))
		main.fx.telegraphs.append({"kind": "boss_line", "pos": global_position,
			"dir": dash_dir, "len": 300.0, "color": tel_color,
			"alpha": tw * minf(1.0, dash_t / 0.45)})
		sprite.modulate = Color8(0xff, 0xdd, 0xdd)
		if dash_t >= 0.45:
			dash_state = "dash"
			dash_t = 0.0
			sprite.modulate = BOSS_TINT.get(boss_type, Color.WHITE)
	elif dash_state == "dash":
		dash_t += dt
		var dash_sp := 450.0 if boss_type == "wolf_king" else 400.0
		velocity = dash_dir * dash_sp
		if dist < 110.0 and not player.is_invincible():
			var base := 18.0 if boss_type == "wolf_king" else 24.0
			main.hazard_damage(base, 0.9, Color.WHITE, "")
		# 바위에 박으면 기절 (긴 빈틈)
		var crashed := false
		if main.terrain:
			for obs in main.terrain.obstacles:
				if Vector2(global_position.x - obs.x, global_position.y - obs.y).length() < obs.r + 60.0:
					crashed = true
					break
		if crashed:
			velocity = Vector2.ZERO
			global_position -= dash_dir * 18.0
			dash_state = "stunned"
			stun_t = 0.0
			stun_dur = 1.7
			vulnerable = true
			vuln_mult = 2.0
			main.spawn_impact(global_position, 90.0, Color8(0xdd, 0xcc, 0x88))
			main.fx.add_particles(global_position, Color8(0xdd, 0xcc, 0x88), 18)
			if main.skills:
				main.skills.trigger_flash(Color8(0xff, 0xee, 0xcc), 0.22)
			main.add_shake(0.22, 9.0)
		elif dash_t >= 0.32:
			dash_state = "recover"
			recover_t = 0.0
			recover_dur = 0.9
			vulnerable = true
			vuln_mult = 1.6
			velocity = Vector2.ZERO
	elif dash_state == "stunned":
		velocity = Vector2.ZERO
		stun_t += dt
		sprite.modulate = Color8(0xff, 0xe0, 0x7a)
		if stun_t >= stun_dur:
			dash_state = "idle"
			vulnerable = false
			atk_timer = 0.0
			sprite.modulate = BOSS_TINT.get(boss_type, Color.WHITE)
	elif dash_state == "recover":
		velocity = Vector2.ZERO
		recover_t += dt
		sprite.modulate = Color8(0xff, 0xd0, 0xa0)
		if recover_t >= recover_dur:
			dash_state = "idle"
			vulnerable = false
			atk_timer = 0.0
			sprite.modulate = BOSS_TINT.get(boss_type, Color.WHITE)


# ── 코끼리(최종): 느린 추격 + 메테오 궁극기 + 근접 피해 ───────
func _pattern_elephant(dt: float, dist: float, dir: Vector2, p: Dictionary) -> void:
	velocity = dir * 48.0 if dist > 100.0 else Vector2.ZERO
	atk_timer += dt
	if atk_timer >= atk_interval:
		atk_timer = 0.0
		_spawn_meteors(p)
	if dist < 100.0 and not player.is_invincible():
		main.hazard_damage(18.0, 0.9, Color.WHITE, "")


# ── 메테오 소환 (mino1 _spawnMeteors) — 5~6발, 1발은 정조준 ──
func _spawn_meteors(p: Dictionary) -> void:
	var count := 5 + (1 if randf() < 0.5 else 0)
	for i in count:
		var spread := 0.0 if i == 0 else 100.0
		var tx := clampf(p["x"] + (randf() * 2.0 - 1.0) * spread, 40.0, GameData.WORLD_W - 40.0)
		var ty := clampf(p["y"] + (randf() * 2.0 - 1.0) * spread, 40.0, GameData.WORLD_H - 40.0)
		meteors.append({"tx": tx, "ty": ty, "warn_t": 1.0, "falling": false,
			"fall_y": ty - 460.0, "hit": false, "hit_t": 0.0})


# ── 메테오 갱신 (mino1 _updateMeteors) ─────────────────────
func _update_meteors(dt: float, p: Dictionary) -> void:
	for i in range(meteors.size() - 1, -1, -1):
		var m: Dictionary = meteors[i]
		if m["hit"]:
			m["hit_t"] = float(m["hit_t"]) + dt
			if float(m["hit_t"]) >= 0.45:
				meteors.remove_at(i)
			continue
		if float(m["warn_t"]) > 0.0:
			m["warn_t"] = float(m["warn_t"]) - dt
			if float(m["warn_t"]) <= 0.0:
				m["falling"] = true
			continue
		if m["falling"]:
			m["fall_y"] = float(m["fall_y"]) + 920.0 * dt
			if float(m["fall_y"]) >= float(m["ty"]):
				m["fall_y"] = m["ty"]
				m["hit"] = true
				m["hit_t"] = 0.0
				main.add_shake(0.12, 6.0)
				Audio.boom()   # 운석 폭발 (mino1 MinoSound.boom)
				# 착탄 피해 (반경 60, 방어 관통식 hazard)
				if Vector2(p["x"] - float(m["tx"]), p["y"] - float(m["ty"])).length() < 60.0 and not player.is_invincible():
					main.hazard_damage(26.0, 0.9, Color.WHITE, "")


# ── 보스 피격 (Main._update_combat 이 호출) — HP 차감·찌그러짐 ──
func take_hit(dmg: float) -> void:
	if dead:
		return
	hp -= dmg
	var bs := base_scale
	sprite.modulate = Color.WHITE
	if hit_tween and hit_tween.is_valid():
		hit_tween.kill()
	sprite.scale = Vector2(bs.x * 1.18, bs.y * 0.85)
	hit_tween = create_tween()
	hit_tween.tween_interval(0.08)
	hit_tween.tween_callback(func(): sprite.scale = Vector2(bs.x * 0.9, bs.y * 1.12))
	hit_tween.tween_interval(0.065)
	hit_tween.tween_callback(func():
		sprite.scale = bs
		sprite.modulate = BOSS_TINT.get(boss_type, Color.WHITE))


# ── 보스 사망 (mino1 _killBoss) — 대폭발·드랍·골드·챕터 클리어 ──
func _die() -> void:
	if dead:
		return
	dead = true
	set_physics_process(false)
	if has_node("CollisionShape2D"):
		$CollisionShape2D.set_deferred("disabled", true)
	var bx := global_position
	# 대폭발 연출
	main.spawn_impact(bx, 100.0, Color8(0xff, 0x88, 0x00))
	main.spawn_impact(bx + Vector2(40, -20), 70.0, Color8(0xff, 0xcc, 0x00))
	main.fx.add_particles(bx, Color8(0xff, 0x88, 0x00), 30)
	main.fx.add_particles(bx + Vector2(40, -20), Color8(0xff, 0xcc, 0x00), 25)
	main.fx.add_particles(bx + Vector2(-30, 10), Color8(0xff, 0x44, 0x22), 20)
	main.add_shake(0.4, 14.0)
	# 보스 드랍 (전설급 보장) + 골드
	main.on_boss_died(bx)
	# 보스 패턴 그리기 정리
	if _pattern_draw and is_instance_valid(_pattern_draw):
		_pattern_draw.queue_free()
	if _hp_layer and is_instance_valid(_hp_layer):
		_hp_layer.queue_free()
	queue_free()


# ── HP 잔상 갱신 (mino1 _drawBossHP 의 trail 감쇠) ──────────
func _update_hp_trail(dt: float) -> void:
	if _hp_trail > hp:
		_hp_trail = maxf(hp, _hp_trail - maxhp * dt * 0.35)
	if _hp_draw:
		_hp_draw.queue_redraw()
	_update_hp_labels()


func _update_hp_labels() -> void:
	var vp := get_viewport().get_visible_rect().size
	var bar_w := minf(vp.x * 0.68, 460.0)
	var bar_x := (vp.x - bar_w) / 2.0
	if _hp_label:
		_hp_label.size = Vector2(vp.x, 20)
		_hp_label.position = Vector2(0, 14)
	if _hp_pct_label:
		var pct := int(ceil(maxf(0.0, hp / maxhp) * 100.0))
		_hp_pct_label.text = "%d / %d  (%d%%)" % [maxi(0, int(hp)), int(maxhp), pct]
		_hp_pct_label.size = Vector2(bar_w, 18)
		_hp_pct_label.position = Vector2(bar_x, 36.0 + 1.0)


# ── 걷기 의사 애니 + 그림자 ─────────────────────────────────
func _walk_anim(dt: float, moving: bool) -> void:
	walk_t += dt
	if hit_tween and hit_tween.is_valid():
		return
	var bs := base_scale
	if moving:
		var bob := 1.0 + absf(sin(walk_t * 6.0)) * 0.04
		sprite.scale = Vector2(bs.x, bs.y * bob)
		var lift := absf(sin(walk_t * 6.0)) * 4.0
		shadow.scale = Vector2(1.0 - lift / 40.0, 1.0 - lift / 40.0)
		shadow.modulate.a = 0.32 * (1.0 - lift / 60.0)
	else:
		var breathe := 1.0 + sin(walk_t * 1.4) * 0.02
		sprite.scale = Vector2(bs.x * breathe, bs.y / breathe)
		shadow.scale = Vector2.ONE
		shadow.modulate.a = 0.32


# ── 보스 HP 바 그리기 스크립트 (화면 고정) (mino1 _drawBossHP) ──
func _make_hp_draw_script() -> GDScript:
	var src := """
extends Node2D
var boss
func _draw():
	if boss == null:
		return
	var vp = get_viewport().get_visible_rect().size
	var w = min(vp.x * 0.68, 460.0)
	var x = (vp.x - w) / 2.0
	var y = 36.0
	var h = 18.0
	var pct = max(0.0, boss.hp / boss.maxhp)
	var trail_pct = max(0.0, boss._hp_trail / boss.maxhp)
	# 외곽 어두운 박스
	draw_rect(Rect2(x - 8, y - 16, w + 16, h + 32), Color(0, 0, 0, 0.75), true)
	draw_rect(Rect2(x - 8, y - 16, w + 16, h + 32), Color(0.54, 0.13, 0.13, 0.9), false, 2.0)
	# HP 바 배경
	draw_rect(Rect2(x, y, w, h), Color(0.23, 0.03, 0.03), true)
	# 잔상(주황, 실제보다 뒤처짐)
	if trail_pct > pct:
		draw_rect(Rect2(x, y, w * trail_pct, h), Color(1.0, 0.4, 0.13, 0.7), true)
	# 실제 HP (색 변화)
	var hp_col = Color(0.9, 0.19, 0.19)
	if pct <= 0.28:
		hp_col = Color(1.0, 0.07, 0.07)
	elif pct <= 0.55:
		hp_col = Color(1.0, 0.4, 0.13)
	if pct > 0.0:
		draw_rect(Rect2(x, y, w * pct, h), hp_col, true)
		if pct > 0.05:
			draw_rect(Rect2(x + 2, y + 2, (w - 4) * pct, 5), Color(1, 1, 1, 0.22), true)
	draw_rect(Rect2(x, y, w, h), Color(1.0, 0.6, 0.4, 0.6), false, 1.5)
"""
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


# ── 보스 패턴 그리기 스크립트 (월드 좌표: 기절별·독장판·메테오) ──
func _make_pattern_script() -> GDScript:
	var src := """
extends Node2D
var boss
func _process(_d):
	queue_redraw()
func _draw():
	if boss == null or not is_instance_valid(boss):
		return
	# 기절 별 (멧돼지/늑대가 바위에 박혀 기절)
	if boss.dash_state == 'stunned':
		var cx = boss.global_position.x
		var cy = boss.global_position.y - boss.BOSS_H.get(boss.boss_type, 160.0) * 0.7
		for sidx in 3:
			var a = boss.stun_t * 6.0 + sidx * (TAU / 3.0)
			draw_circle(Vector2(cx + cos(a) * 26.0, cy + sin(a) * 9.0), 4.0, Color(1.0, 0.94, 0.29, 0.9))
	# 악어 독 장판
	for po in boss.poisons:
		var t = po['t']
		var life = po['life']
		var alpha = max(0.0, 1.0 - t / life) * 0.7
		var pulse = 0.55 + 0.45 * abs(sin(t * 3.0))
		var c = Vector2(po['x'], po['y'])
		draw_circle(c, 44.0, Color(0.13, 0.8, 0.27, alpha * pulse))
		draw_arc(c, 44.0, 0.0, TAU, 28, Color(0.53, 1.0, 0.27, alpha * 0.8), 2.0)
	# 코끼리 메테오 (예고원 → 낙하 → 폭발)
	for m in boss.meteors:
		var mc = Vector2(m['tx'], m['ty'])
		if m['hit']:
			var hp2 = m['hit_t'] / 0.45
			if hp2 < 1.0:
				draw_circle(mc, 68.0 * (1.0 - hp2), Color(1.0, 0.29, 0.14, (1.0 - hp2) * 0.8))
			continue
		if m['warn_t'] > 0.0:
			var pulse2 = 0.5 + 0.5 * sin(m['warn_t'] * 10.0)
			draw_arc(mc, 50.0, 0.0, TAU, 32, Color(1.0, 0.24, 0.16, 0.85 * pulse2), 3.0)
			draw_circle(mc, 50.0, Color(1.0, 0.24, 0.16, 0.12 * pulse2))
			continue
		if m['falling']:
			var fp = Vector2(m['tx'], m['fall_y'])
			draw_rect(Rect2(fp.x - 8.0, fp.y - 52.0, 16.0, 52.0), Color(1.0, 0.67, 0.16, 0.6), true)
			draw_circle(fp, 11.0, Color(0.29, 0.23, 0.19))
			draw_circle(fp, 8.0, Color(1.0, 0.85, 0.52))
"""
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _show_warn() -> void:
	var entry: Array = BOSS_WARN.get(boss_type, ["⚠ 보스 등장!", Color8(0xff, 0x44, 0x44)])
	var lbl := _mk_label(str(entry[0]), 22, entry[1])
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var vp := get_viewport().get_visible_rect().size
	lbl.size = Vector2(vp.x, 30)
	lbl.position = Vector2(0, 76)
	_hp_layer.add_child(lbl)
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): if is_instance_valid(lbl): lbl.queue_free())


func _mk_label(txt: String, sz: int, col: Color) -> Label:
	var l := Label.new()
	if main and main.has_method("get_kfont") and main.get_kfont():
		l.add_theme_font_override("font", main.get_kfont())
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color8(0x1a, 0x1a, 0x1a))
	l.add_theme_constant_override("outline_size", 4)
	l.text = txt
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


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
