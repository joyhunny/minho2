extends CharacterBody2D
class_name Player
## Player — 주인공. mino1 의 this.hero 에 해당.
## 이동: 가상 조이스틱(화면 왼쪽 60% 터치) + 키보드(WASD/화살표). 속도는 GameState.player.sp.
## S0 단계: 이동·바라보는 방향·그림자·살짝 흔들리는 의사 애니까지. 공격·피격은 S1.

const AI_HERO_H := 88.0       # 표시 높이(px) — mino1 과 동일
const PERSP_SQUASH := 0.92    # 미세 원근(비스듬 시점) — mino1 과 동일

@onready var sprite: Sprite2D = $Sprite
@onready var shadow: Sprite2D = $Shadow

var base_scale := Vector2.ONE   # 의사 애니용 기본 스케일 (원근 반영 후)
var move_dir := Vector2.ZERO    # 이번 프레임 이동 방향(-1~1)
var face := 1                   # 바라보는 방향 (+1 오른쪽 / -1 왼쪽)
var walk_t := 0.0               # 걷기 의사 애니 위상
var idle_t := 0.0               # idle 호흡 위상

# ── 전투 상태 (mino1 _updateCombat / _applyHeroAnim) ────────
var atk_swing_t := 0.0          # 공격 스윙 모션 남은 시간 (0.26초)
var lunge_t := 0.0              # 공격 룽지 남은 시간 (0.08초)
var lunge_vx := 0.0            # 룽지 방향 속도
var slash_t := 0.0             # 슬래시 이펙트 남은 시간 (0.22초)

var main: Node = null           # Main 참조 (FX·전투 위임)
var want_attack := false        # 공격 버튼/키 눌림 (Main 이 매 프레임 채움)


func _ready() -> void:
	_setup_sprite()
	_setup_shadow()
	# 저장된 위치에서 시작 (없으면 월드 중앙)
	var p: Dictionary = GameState.player
	global_position = Vector2(p.get("x", GameData.WORLD_W / 2.0), p.get("y", GameData.WORLD_H / 2.0))


func _setup_sprite() -> void:
	var tex := _load_tex("res://assets/sprites/hero.png")
	if tex:
		sprite.texture = tex
		# 표시 높이를 AI_HERO_H 로 맞춘다 (mino1 fitH)
		var h := float(tex.get_height())
		var s := AI_HERO_H / h if h > 0.0 else 1.0
		sprite.scale = Vector2(s, s * PERSP_SQUASH)
		base_scale = sprite.scale
	else:
		# 그림이 없으면 색 도형으로 대체 (검증용)
		var ph := ColorRect.new()
		ph.size = Vector2(40, 70)
		ph.position = Vector2(-20, -70)
		ph.color = Color(0.45, 0.85, 1.0)
		add_child(ph)


func _setup_shadow() -> void:
	# 발밑 타원 그림자 (mino1: ellipse 48x15, alpha 0.28)
	shadow.texture = _make_shadow_tex()
	shadow.modulate = Color(0, 0, 0, 0.28)
	shadow.position = Vector2(0, 4)   # 발 살짝 아래


func _process(delta: float) -> void:
	_read_input()
	# 히트스톱 중엔 애니 시간도 느려진다 (Main 의 time_scale)
	var ts: float = main.time_scale if main else 1.0
	var dt := delta * ts

	# 무적·공격 타이머 감소
	var p: Dictionary = GameState.player
	if float(p.get("inv", 0.0)) > 0.0:
		p["inv"] = maxf(0.0, float(p["inv"]) - dt)
	if float(p.get("atkCD", 0.0)) > 0.0:
		p["atkCD"] = maxf(0.0, float(p["atkCD"]) - dt)

	# 걷기 의사 애니 (mino1 _applyHeroAnim)
	var hbs := base_scale
	if move_dir.length() > 0.08:
		walk_t += dt * 12.0
		var bounce := absf(sin(walk_t))
		sprite.position.y = -bounce * 5.0
		sprite.rotation = sin(walk_t) * 0.06
		sprite.scale = Vector2(hbs.x * face * (1.0 - bounce * 0.04), hbs.y * (1.0 + bounce * 0.04))
	else:
		walk_t = 0.0
		idle_t += dt
		var breathe := 1.0 + sin(idle_t * 1.4) * 0.025
		sprite.position.y = lerpf(sprite.position.y, 0.0, dt * 10.0)
		sprite.rotation = lerpf(sprite.rotation, 0.0, dt * 10.0)
		sprite.scale = Vector2(hbs.x * face * breathe, hbs.y / breathe)

	# 공격 스윙: 휘두르는 동작 (걷기/idle 위에 덮어씀) (mino1)
	if atk_swing_t > 0.0:
		atk_swing_t -= dt
		var sw := maxf(0.0, atk_swing_t) / 0.26   # 1 → 0
		var arc := sin((1.0 - sw) * PI)            # 0 → 1 → 0
		sprite.rotation = face * arc * 0.55
		sprite.scale = Vector2(hbs.x * face * (1.0 + arc * 0.10), hbs.y * (1.0 - arc * 0.06))

	# 슬래시 이펙트 타이머 (Main 의 슬래시 드로잉용)
	if slash_t > 0.0:
		slash_t -= dt

	# 피격 무적 깜빡임 (mino1: p.inv 동안 반짝)
	if float(p.get("inv", 0.0)) > 0.0 and int(p["inv"] * 16.0) % 2 == 0:
		sprite.modulate.a = 0.3
	else:
		sprite.modulate.a = 1.0


func _physics_process(delta: float) -> void:
	var ts: float = main.time_scale if main else 1.0
	var sp := float(GameState.player.get("sp", 165))
	velocity = move_dir * sp * ts
	move_and_slide()

	# 공격 룽지: 공격 방향으로 짧게 찌름 (mino1 _updateCombat lunge)
	if lunge_t > 0.0:
		var dt := delta * ts
		lunge_t -= dt
		if lunge_t > 0.0:
			global_position.x += lunge_vx * dt

	# 월드 경계 안에 가둔다 (mino1: setCollideWorldBounds)
	global_position.x = clampf(global_position.x, 0.0, GameData.WORLD_W)
	global_position.y = clampf(global_position.y, 0.0, GameData.WORLD_H)
	# 상태에 위치 반영 (저장용)
	GameState.player["x"] = global_position.x
	GameState.player["y"] = global_position.y


# ── 입력 수집: 키보드 + 가상 조이스틱(Main이 채워줌) ──────────
var joy_vec := Vector2.ZERO   # Main 의 조이스틱이 매 프레임 넣어준다 (-1~1)

func _read_input() -> void:
	var kb := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		kb.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		kb.x += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		kb.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		kb.y += 1.0

	var v := kb if kb.length() > 0.01 else joy_vec
	if v.length() > 1.0:
		v = v.normalized()
	move_dir = v

	# 바라보는 방향 갱신 (좌우로 움직일 때만)
	if absf(v.x) > 0.05:
		face = 1 if v.x > 0.0 else -1
		GameState.player["face"] = face


# ── 공격 실행 — Main 의 전투 루프가 명중 가능할 때 호출 ──────
# mino1 _updateCombat: 공격 쿨다운·룽지·스윙·슬래시를 켠다. 명중 판정은 Main.
func start_attack() -> void:
	var p: Dictionary = GameState.player
	p["atkCD"] = float(p.get("atkSpeed", 0.5))
	atk_swing_t = 0.26
	slash_t = 0.22
	lunge_t = 0.08
	lunge_vx = face * 120.0


func can_attack() -> bool:
	return float(GameState.player.get("atkCD", 0.0)) <= 0.0


# ── 피격 — 적 AI 가 호출. 무적 중이면 무시 (mino1 _incomingDmg 적용) ──
func hurt(raw_dmg: float, inv_dur: float) -> void:
	if is_invincible():
		return
	var p: Dictionary = GameState.player
	var armor := float(p.get("armor", 0.0))
	# mino1 _incomingDmg: 비율 방어 (절대 0 안 됨)
	var real := maxf(1.0, round(raw_dmg * 70.0 / (70.0 + armor)))
	p["hp"] = maxf(0.0, float(p["hp"]) - real)
	p["inv"] = inv_dur
	if main and main.has_method("spawn_float_text"):
		main.spawn_float_text(global_position, str(int(real)), false)
	if main and main.has_method("on_player_hurt"):
		main.on_player_hurt(real)


func is_invincible() -> bool:
	return float(GameState.player.get("inv", 0.0)) > 0.0


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null


# 부드러운 타원 그림자 텍스처를 코드로 생성 (외부 에셋 없이)
func _make_shadow_tex() -> ImageTexture:
	var w := 48
	var h := 16
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
