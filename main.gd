extends Node2D

# minho2 — 첫 Godot 시범 게임: "떨어지는 별 받기"
# (아직 그림 없음 — 일부러 색 도형으로만. 에셋은 나중에 입힌다.)
# 조작: 왼/오른 화살표 또는 A·D 키, 또는 화면을 손으로 누르거나 끌기.
# ※ 게임 화면 글자는 영어로 둠 — Godot 기본 폰트엔 한글 글리프가 없어 깨질 수 있어서.
#    (나중에 한글 폰트 파일을 넣으면 한글로 바꾼다.)

var screen_size: Vector2
var basket: ColorRect
var basket_w := 150.0
var basket_h := 42.0
var basket_speed := 950.0

var stars: Array = []
var spawn_timer := 0.0
var spawn_interval := 0.9
var fall_speed := 320.0

var score := 0
var lives := 3
var score_label: Label
var info_label: Label
var over_label: Label
var game_over := false

var target_x := -1.0   # 손가락/마우스로 이동할 목표 x (-1 = 없음)

func _ready() -> void:
	screen_size = get_viewport_rect().size

	# 배경
	var bg := ColorRect.new()
	bg.size = screen_size
	bg.color = Color(0.08, 0.10, 0.18)
	add_child(bg)

	# 바구니(플레이어)
	basket = ColorRect.new()
	basket.size = Vector2(basket_w, basket_h)
	basket.color = Color(0.45, 0.85, 1.0)
	basket.position = Vector2(screen_size.x * 0.5 - basket_w * 0.5, screen_size.y - 150.0)
	add_child(basket)

	# 점수
	score_label = Label.new()
	score_label.add_theme_font_size_override("font_size", 56)
	score_label.position = Vector2(28, 24)
	add_child(score_label)

	# 안내
	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 28)
	info_label.position = Vector2(28, 96)
	add_child(info_label)

	# 게임 오버 (가운데)
	over_label = Label.new()
	over_label.add_theme_font_size_override("font_size", 64)
	over_label.position = Vector2(0, screen_size.y * 0.4)
	over_label.size = Vector2(screen_size.x, 160)
	over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_label.visible = false
	add_child(over_label)

	_update_labels()

func _update_labels() -> void:
	score_label.text = "Score: %d" % score
	info_label.text = "Catch the stars!   arrows / A D / tap   |   Lives: %d" % lives
	over_label.text = "GAME OVER\n(tap or Enter)"
	over_label.visible = game_over

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			target_x = event.position.x
			if game_over:
				_restart()
	elif event is InputEventScreenDrag:
		target_x = event.position.x
	elif event is InputEventMouseButton:
		if event.pressed:
			target_x = event.position.x
			if game_over:
				_restart()
	elif event is InputEventMouseMotion:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			target_x = event.position.x
	elif event is InputEventKey:
		if event.pressed and event.keycode == KEY_ENTER and game_over:
			_restart()

func _process(delta: float) -> void:
	if game_over:
		return
	_move_basket(delta)
	_spawn_stars(delta)
	_update_stars(delta)

func _move_basket(delta: float) -> void:
	var dir := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		dir -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dir += 1.0
	if dir != 0.0:
		basket.position.x += dir * basket_speed * delta
		target_x = -1.0
	elif target_x >= 0.0:
		var center := basket.position.x + basket_w * 0.5
		var diff := target_x - center
		var step := basket_speed * delta
		if abs(diff) <= step:
			basket.position.x = target_x - basket_w * 0.5
		else:
			basket.position.x += signf(diff) * step
	basket.position.x = clampf(basket.position.x, 0.0, screen_size.x - basket_w)

func _spawn_stars(delta: float) -> void:
	spawn_timer += delta
	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		var sz := 48.0
		var s := ColorRect.new()
		s.size = Vector2(sz, sz)
		s.color = Color(1.0, 0.85, 0.3)
		s.position = Vector2(randf_range(0.0, screen_size.x - sz), -sz)
		add_child(s)
		stars.append(s)
		# 점점 빠르고 잦게 (난이도 상승)
		if spawn_interval > 0.42:
			spawn_interval -= 0.02
		fall_speed += 5.0

func _update_stars(delta: float) -> void:
	var basket_rect := Rect2(basket.position, basket.size)
	for s in stars.duplicate():
		s.position.y += fall_speed * delta
		var s_rect := Rect2(s.position, s.size)
		if s_rect.intersects(basket_rect):
			score += 1
			_remove_star(s)
			_update_labels()
		elif s.position.y > screen_size.y:
			lives -= 1
			_remove_star(s)
			if lives <= 0:
				game_over = true
			_update_labels()

func _remove_star(s: ColorRect) -> void:
	stars.erase(s)
	s.queue_free()

func _restart() -> void:
	for s in stars:
		s.queue_free()
	stars.clear()
	score = 0
	lives = 3
	spawn_interval = 0.9
	fall_speed = 320.0
	spawn_timer = 0.0
	game_over = false
	basket.position.x = screen_size.x * 0.5 - basket_w * 0.5
	target_x = -1.0
	_update_labels()
