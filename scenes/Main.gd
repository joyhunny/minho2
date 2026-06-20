extends Node2D
## Main — 메인 게임 루프. mino1 의 PlayScene 에 해당.
## S0: 2200x2200 월드 + 풀밭(타일) 배경 + 플레이어 추적 카메라 + 플레이어 + 가상 조이스틱.
## 적·전투·HUD 등은 다음 단계(S1~)에서 이 위에 쌓는다.

const FONT_PATH := "res://fonts/Jua-Regular.ttf"
const PLAYER_SCENE := preload("res://scenes/Player.tscn")

const GRASS_TILE := 384       # mino1 grass_soft 타일 크기
const JOY_MAX := 62.0         # 조이스틱 최대 반경 (mino1 과 동일)
const JOY_RADIUS := 64.0      # 베이스 원 표시 반경

var kfont: Font
var player: CharacterBody2D
var camera: Camera2D

# 가상 조이스틱 상태 (mino1: this.joy)
var joy_active := false
var joy_id := -1
var joy_base := Vector2.ZERO   # 처음 누른 화면 위치
var joy_knob := Vector2.ZERO   # 현재 손가락 위치(반경 제한)
var joy_vec := Vector2.ZERO    # -1~1 방향
var joy_layer: CanvasLayer
var joy_draw: Node2D

var info_label: Label


func _ready() -> void:
	if ResourceLoader.exists(FONT_PATH):
		kfont = load(FONT_PATH)

	_build_world()
	_build_player()
	_build_camera()
	_build_joystick()
	_build_info()


# ── 월드: 풀밭 타일 배경 (2200x2200) ────────────────────────
func _build_world() -> void:
	# 현재 지역 색조 (mino1: REGION_DEFS[region].ground_tint)
	var region_idx: int = clampi(GameState.region, 0, GameData.REGION_DEFS.size() - 1)
	var tint: Color = GameData.REGION_DEFS[region_idx]["ground_tint"]

	var bg := Sprite2D.new()
	bg.name = "Ground"
	bg.texture = _make_grass_tex()
	bg.region_enabled = true
	bg.region_rect = Rect2(0, 0, GameData.WORLD_W, GameData.WORLD_H)
	# region_rect 가 타일 텍스처를 반복(타일링)하게 하려면 texture_repeat 필요
	bg.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	bg.centered = false
	bg.position = Vector2.ZERO
	bg.modulate = tint
	bg.z_index = -100
	add_child(bg)

	# 월드 테두리(경계 시각화) — 어두운 선
	var border := Line2D.new()
	border.name = "WorldBorder"
	border.points = PackedVector2Array([
		Vector2(0, 0), Vector2(GameData.WORLD_W, 0),
		Vector2(GameData.WORLD_W, GameData.WORLD_H), Vector2(0, GameData.WORLD_H),
		Vector2(0, 0),
	])
	border.width = 6.0
	border.default_color = Color(0.10, 0.13, 0.08, 0.8)
	border.z_index = -90
	add_child(border)


func _build_player() -> void:
	player = PLAYER_SCENE.instantiate()
	add_child(player)


func _build_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera"
	# 플레이어를 부드럽게 따라간다 (mino1: startFollow lerp 0.14)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	# 카메라가 월드 밖을 안 보이게 경계 제한
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(GameData.WORLD_W)
	camera.limit_bottom = int(GameData.WORLD_H)
	player.add_child(camera)
	camera.make_current()


# ── 가상 조이스틱 (mino1: setupJoystick/drawJoystick) ────────
func _build_joystick() -> void:
	joy_layer = CanvasLayer.new()
	joy_layer.name = "JoyLayer"
	add_child(joy_layer)
	joy_draw = Node2D.new()
	joy_draw.name = "JoyDraw"
	joy_draw.set_script(_make_joy_draw_script())
	joy_draw.set("main", self)
	joy_layer.add_child(joy_draw)


# 조이스틱을 그리는 작은 Node2D 스크립트 (_draw 로 원 그림)
func _make_joy_draw_script() -> GDScript:
	var src := """
extends Node2D
var main
func _process(_d):
	queue_redraw()
func _draw():
	if main == null or not main.joy_active:
		return
	var base = main.joy_base
	var knob = main.joy_knob
	# 베이스 원 (반투명 검정)
	draw_circle(base, 64.0, Color(0, 0, 0, 0.22))
	draw_arc(base, 64.0, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 2.0)
	# 노브 (연두)
	draw_circle(knob, 28.0, Color(0.81, 0.88, 0.69, 0.55))
"""
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _build_info() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	add_child(layer)
	info_label = Label.new()
	if kfont:
		info_label.add_theme_font_override("font", kfont)
	info_label.add_theme_font_size_override("font_size", 30)
	info_label.add_theme_color_override("font_color", Color.WHITE)
	info_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	info_label.add_theme_constant_override("outline_size", 6)
	info_label.position = Vector2(24, 24)
	info_label.text = "왼쪽 화면을 끌어 이동  |  WASD·화살표"
	layer.add_child(info_label)


# ── 입력: 가상 조이스틱 ─────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	# 터치 + 마우스(데스크톱 테스트) 둘 다 처리
	if event is InputEventScreenTouch:
		_handle_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_handle_drag(event.index, event.position)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_touch(-2, event.position, event.pressed)
	elif event is InputEventMouseMotion:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_handle_drag(-2, event.position)


func _handle_touch(id: int, pos: Vector2, pressed: bool) -> void:
	var vp_w := get_viewport().get_visible_rect().size.x
	if pressed:
		# 화면 왼쪽 60% 에서만 조이스틱 시작 (mino1 과 동일)
		if not joy_active and pos.x < vp_w * 0.6:
			joy_active = true
			joy_id = id
			joy_base = pos
			joy_knob = pos
			joy_vec = Vector2.ZERO
	else:
		if id == joy_id:
			_release_joy()


func _handle_drag(id: int, pos: Vector2) -> void:
	if joy_active and id == joy_id:
		var d := pos - joy_base
		var mag := d.length()
		if mag > JOY_MAX:
			d = d / mag * JOY_MAX
		joy_knob = joy_base + d
		joy_vec = d / JOY_MAX


func _release_joy() -> void:
	joy_active = false
	joy_id = -1
	joy_vec = Vector2.ZERO


func _process(_delta: float) -> void:
	# 조이스틱 방향을 플레이어에 전달
	if player:
		player.joy_vec = joy_vec if joy_active else Vector2.ZERO


# ── 풀밭 텍스처 생성 (mino1: grass_soft, 오염된 땅) ───────────
func _make_grass_tex() -> ImageTexture:
	var s := GRASS_TILE
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	# 베이스: 어두운 녹갈색 (오염된 흙)
	img.fill(Color8(0x2e, 0x3d, 0x1f))

	var rng := GameData.make_rng(99)
	# 레이어 1: 큰 오염 음영 패치 (갈색·이끼)
	var base_tones := [Color8(0x3a, 0x4a, 0x22), Color8(0x28, 0x32, 0x1a),
		Color8(0x3f, 0x4d, 0x25), Color8(0x24, 0x30, 0x16), Color8(0x33, 0x42, 0x28)]
	for i in 80:
		_blob(img, rng, base_tones[i % base_tones.size()], 0.22, 18.0, 55.0, s)
	# 레이어 2: 보라/독성 오염 얼룩
	var tox_tones := [Color8(0x5a, 0x1e, 0x7a), Color8(0x6b, 0x2d, 0x8c),
		Color8(0x45, 0x15, 0x60), Color8(0x7a, 0x3a, 0x9a)]
	for i in 40:
		_blob(img, rng, tox_tones[i % tox_tones.size()], 0.11, 10.0, 32.0, s)
	# 레이어 3: 건조한 황갈색 흙 패치
	for i in 50:
		_blob(img, rng, Color8(0x5c, 0x4a, 0x2a), 0.10, 8.0, 24.0, s)
	# 레이어 4: 밝기 변화 (노이즈 느낌)
	for i in 60:
		_blob(img, rng, Color8(0x4a, 0x5c, 0x2a), 0.07, 4.0, 12.0, s)

	return ImageTexture.create_from_image(img)


# 원형 얼룩 하나를 알파 블렌딩으로 찍는다 (mino1 fillCircle 대응)
func _blob(img: Image, rng: GameData.RNG, col: Color, alpha: float, rmin: float, rmax: float, s: int) -> void:
	var cx := rng.range_f(0.0, float(s))
	var cy := rng.range_f(0.0, float(s))
	var rad := rng.range_f(rmin, rmax)
	var r2 := rad * rad
	var x0 := maxi(0, int(cx - rad))
	var x1 := mini(s - 1, int(cx + rad))
	var y0 := maxi(0, int(cy - rad))
	var y1 := mini(s - 1, int(cy + rad))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := x - cx
			var dy := y - cy
			if dx * dx + dy * dy <= r2:
				var dst := img.get_pixel(x, y)
				img.set_pixel(x, y, dst.lerp(col, alpha))
