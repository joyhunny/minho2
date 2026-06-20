extends Node2D
## Companion — 동료 카피바라 (mino1 _capybara / _updateCapybara / _drawCapySpeech).
## 주인공을 부드럽게 따라오고, 4초마다 가까이 있으면 HP 를 회복시켜 주고,
## 상황별 말풍선 대사를 띄운다. assets/sprites/capybara.png 사용.
##
## Main 이 _build_companion() 에서 만들어 붙인다. main 참조로 player·terrain 을 읽는다.

const FOLLOW_DIST := 55.0
const HEAL_INTERVAL := 4.0
const HEAL_AMT := 9.0
const CAPY_H := 60.0           # 표시 높이(px) — mino1 fitH(60)
const PERSP_SQUASH := 0.92

var main: Node = null
var sprite: Sprite2D = null
var shadow: Sprite2D = null
var base_scale := Vector2.ONE

var bounce_t := 0.0
var heal_timer := 0.0

# 말풍선 상태 (mino1 _capySpeech*)
var speech_msg := ""
var speech_t := 0.0           # 표시 남은 시간
var speech_cool := 8.0        # 다음 대사까지 쿨다운
var speech_label: Label = null
var bubble: Node2D = null     # 말풍선 배경 그리기 노드


func _ready() -> void:
	z_index = 0
	# 그림자
	shadow = Sprite2D.new()
	shadow.texture = _make_shadow_tex()
	shadow.modulate = Color(0, 0, 0, 0.26)
	add_child(shadow)
	# 스프라이트
	sprite = Sprite2D.new()
	var tex := _load_tex("res://assets/sprites/capybara.png")
	if tex:
		sprite.texture = tex
		var h := float(tex.get_height())
		var s := CAPY_H / h if h > 0.0 else 1.0
		sprite.scale = Vector2(s, s * PERSP_SQUASH)
		base_scale = sprite.scale
	else:
		var ph := Image.create(46, 36, false, Image.FORMAT_RGBA8)
		ph.fill(Color8(0xb0, 0x88, 0x55))
		sprite.texture = ImageTexture.create_from_image(ph)
		base_scale = Vector2.ONE
	add_child(sprite)
	# 말풍선 그리기 노드 (스프라이트 위)
	bubble = Node2D.new()
	bubble.set_script(_make_bubble_script())
	bubble.set("owner_companion", self)
	bubble.z_index = 200
	add_child(bubble)
	# 말풍선 글자
	speech_label = Label.new()
	var kf = main.get_kfont() if main and main.has_method("get_kfont") else null
	if kf:
		speech_label.add_theme_font_override("font", kf)
	speech_label.add_theme_font_size_override("font_size", 13)
	speech_label.add_theme_color_override("font_color", Color8(0x33, 0x33, 0x33))
	speech_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speech_label.z_index = 201
	speech_label.visible = false
	add_child(speech_label)
	# 시작 위치 — 주인공 옆
	if main and main.player:
		global_position = main.player.global_position + Vector2(60, 0)


func _process(delta: float) -> void:
	if main == null or main.player == null:
		return
	var ts: float = main.time_scale if "time_scale" in main else 1.0
	var dt := delta * ts
	var p: Dictionary = GameState.player
	var pl: Node2D = main.player

	# ── 따라오기 (lerp, 거리 55px) (mino1) ──
	var ground_y := global_position.y
	var d := pl.global_position - global_position
	var dist := d.length()
	if dist < 1.0:
		dist = 1.0
	if dist > FOLLOW_DIST + 10.0:
		var spd := 180.0 if dist > 200.0 else 100.0
		var target := pl.global_position - (d / dist) * FOLLOW_DIST
		var lerp_amt := minf(1.0, spd * dt / maxf(dist, 1.0))
		global_position += (target - global_position) * lerp_amt
		ground_y = global_position.y

	# 이동 방향으로 좌우반전
	sprite.flip_h = d.x > 0.0

	# 2.5D 보행 바운스
	var moving := dist > FOLLOW_DIST + 12.0
	bounce_t += dt * (9.0 if moving else 3.0)
	var lift := absf(sin(bounce_t)) * (6.0 if moving else 1.5)
	z_index = int(ground_y)
	sprite.position = Vector2(0, -lift)
	sprite.rotation = sin(bounce_t) * 0.05 if moving else 0.0
	shadow.position = Vector2(0, 4)

	# ── 주기적 치유 (4초마다, 가까우면 HP +9) (mino1) ──
	heal_timer += dt
	if heal_timer >= HEAL_INTERVAL:
		heal_timer = 0.0
		if dist < 120.0 and float(p.get("hp", 0)) < float(p.get("maxhp", 0)):
			p["hp"] = minf(float(p["maxhp"]), float(p["hp"]) + HEAL_AMT)
			_show_heal_effect()
			Audio.heal()   # 치유 소리 (mino1 MinoSound.heal)

	# ── 말풍선 (상황별 대사) (mino1) ──
	_update_speech(dt, dist)
	bubble.queue_redraw()


func _update_speech(dt: float, dist: float) -> void:
	var p: Dictionary = GameState.player
	if speech_t > 0.0:
		speech_t -= dt
		# 말풍선 위치: 카피바라 위
		speech_label.visible = true
		var w := speech_msg.length() * 8.0 + 16.0
		speech_label.size = Vector2(w, 20)
		speech_label.position = Vector2(-w / 2.0, -56.0 - 20.0)
		speech_label.text = speech_msg
		if speech_t <= 0.0:
			speech_label.visible = false
			speech_label.text = ""
		return
	speech_cool -= dt
	if speech_cool > 0.0:
		return
	# 쿨다운 끝 — 상황 판단 후 대사 결정 (mino1)
	var msg := ""
	var hp_ratio := float(p.get("hp", 1)) / maxf(1.0, float(p.get("maxhp", 1)))
	var near_poison := false
	var near_buff := false
	if main.terrain:
		near_poison = main.terrain.poison_active
		near_buff = main.terrain.buff_active
	var boss_alive: bool = main.boss != null and is_instance_valid(main.boss)

	if not main.boss_spawned and int(p.get("kills", 0)) == 0:
		msg = "함께 가요, 희망님!"
	elif hp_ratio < 0.3:
		msg = "무리하지 마세요!"
	elif boss_alive:
		msg = "군주가 깨어났어요… 조심해요!"
	elif near_poison:
		msg = "독 웅덩이 조심해요!"
	elif near_buff:
		msg = "저 크리스탈, 힘이 솟아요!"
	else:
		var randoms := [
			"함께라면 무서울 게 없어요!",
			"오염을 정화해요, 희망님!",
			"변이체들을 물리쳐요!",
		]
		msg = randoms[randi() % randoms.size()]

	if msg != "":
		speech_msg = msg
		speech_t = 2.5
		speech_cool = 10.0 + randf() * 6.0


func _show_heal_effect() -> void:
	# 카피바라 위치에 초록 파티클 (Main fx 사용)
	if main.fx:
		main.fx.add_particles(global_position, Color8(0x7e, 0xed, 0x8f), 8)
	# 주인공 위에 회복량 표시
	if main.has_method("spawn_heal_text") and main.player:
		main.spawn_heal_text(main.player.global_position + Vector2(0, -30), "+%d" % int(HEAL_AMT), Color8(0x7e, 0xed, 0x8f))


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _make_shadow_tex() -> ImageTexture:
	var w := 40
	var h := 14
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := w / 2.0
	var cy := h / 2.0
	for y in h:
		for x in w:
			var dx := (x - cx) / cx
			var dy := (y - cy) / cy
			var dd := dx * dx + dy * dy
			if dd <= 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 1.0 - dd * 0.6))
	return ImageTexture.create_from_image(img)


# 말풍선 배경(흰 둥근 사각 + 꼬리)을 그리는 작은 노드 스크립트.
func _make_bubble_script() -> GDScript:
	var src := """
extends Node2D
var owner_companion
func _draw():
	if owner_companion == null:
		return
	if owner_companion.speech_t <= 0.0:
		return
	var msg = owner_companion.speech_msg
	var a = clampf(owner_companion.speech_t / 0.3, 0.0, 1.0)
	var w = msg.length() * 8.0 + 16.0
	var bh = 22.0
	var bx = -w / 2.0
	var by = -56.0 - bh
	var bg = Color(1, 1, 1, 0.92 * a)
	draw_rect(Rect2(bx, by, w, bh), bg, true)
	draw_rect(Rect2(bx, by, w, bh), Color(0.73, 0.73, 0.73, 0.8 * a), false, 1.5)
	# 꼬리 삼각형 (말풍선 → 카피바라)
	var pts = PackedVector2Array([
		Vector2(-6, by + bh), Vector2(6, by + bh), Vector2(0, by + bh + 8)])
	draw_colored_polygon(pts, bg)
"""
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s
