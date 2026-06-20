extends CharacterBody2D
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
	# 걷기 의사 애니: 움직일 때 살짝 위아래·좌우 흔들림 (정지 이미지를 살린다)
	if move_dir.length() > 0.05:
		walk_t += delta * 12.0
		var bob := sin(walk_t) * 0.06
		sprite.scale = Vector2(base_scale.x * face * (1.0 + bob * 0.5), base_scale.y * (1.0 - bob))
		sprite.position.y = -abs(sin(walk_t)) * 3.0
	else:
		# 정지 시 기본 자세로 부드럽게 복귀
		sprite.scale = sprite.scale.lerp(Vector2(base_scale.x * face, base_scale.y), delta * 10.0)
		sprite.position.y = lerpf(sprite.position.y, 0.0, delta * 10.0)


func _physics_process(_delta: float) -> void:
	var sp := float(GameState.player.get("sp", 165))
	velocity = move_dir * sp
	move_and_slide()
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
