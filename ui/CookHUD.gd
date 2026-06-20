extends Control
class_name CookHUD
## CookHUD — 좌하단 요리 HUD: 고기 보유(날/익힘) 패널 + 먹기 버튼 + 굽기 진행 메시지 + 상함 알림.
## mino1 play.js 의 _drawCookingHUD / _eatBtnRect 입력 / _showMeatAlert / cookingMsg 대응.
## 고기 데이터·굽기 로직은 LootSystem(main.loot)에 있고, 여기선 표시 + 먹기 버튼 입력만 한다.

var main: Node = null
var kfont: Font = null
var loot: Node = null            # LootSystem

# 먹기 버튼 (좌하단)
var _eat_rect := Rect2(0, 0, 56, 56)

var _draw_node: Node2D
var _raw_lbl: Label
var _cooked_lbl: Label
var _eat_lbl: Label
var _cook_msg_lbl: Label
var _alert_lbl: Label
var _alert_t := 0.0


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	# 그리기 전용 — 입력은 Main 의 _handle_touch 가 try_eat() 으로 먼저 검사(조이스틱과 충돌 방지)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if main and main.has_method("get_kfont"):
		kfont = main.get_kfont()
	if main:
		loot = main.loot

	_draw_node = Node2D.new()
	_draw_node.set_script(_make_draw_script())
	_draw_node.set("hud", self)
	add_child(_draw_node)

	_raw_lbl = _mk("", 13, Color8(0xff, 0xaa, 0xaa))
	_cooked_lbl = _mk("", 13, Color8(0xff, 0xcc, 0x88))
	_eat_lbl = _mk("", 11, Color.WHITE)
	_eat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cook_msg_lbl = _mk("", 15, Color8(0xff, 0xcc, 0x44))
	_cook_msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alert_lbl = _mk("", 16, Color8(0xff, 0x88, 0x44))
	_alert_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alert_lbl.modulate.a = 0.0


func _process(delta: float) -> void:
	_layout()
	_update_labels(delta)
	_draw_node.queue_redraw()


# 먹기 버튼 위치 (mino1: x=8, y=H-sz-80). 좌하단, 조이스틱 영역과 다른 곳.
func _layout() -> void:
	var sz := 56.0 if size.x <= 460.0 else 52.0
	_eat_rect = Rect2(8.0, size.y - sz - 90.0, sz, sz)


func _update_labels(delta: float) -> void:
	if loot == null:
		return
	var eb := _eat_rect
	# 고기 패널 (먹기 버튼 위)
	var panel_x := eb.position.x
	var panel_y := eb.position.y - 50.0 - 6.0
	if is_instance_valid(_raw_lbl):
		_raw_lbl.text = "× %d  날" % loot.raw_meat
		_raw_lbl.position = Vector2(panel_x + 34.0, panel_y + 8.0)
	if is_instance_valid(_cooked_lbl):
		_cooked_lbl.text = "× %d  익힘" % loot.cooked_meat
		_cooked_lbl.position = Vector2(panel_x + 34.0, panel_y + 28.0)
	# 먹기 버튼 글자
	if is_instance_valid(_eat_lbl):
		_eat_lbl.text = "먹기" if loot.cooked_meat > 0 else ""
		_eat_lbl.size = Vector2(eb.size.x, 16.0)
		_eat_lbl.position = Vector2(eb.position.x, eb.position.y + eb.size.y - 16.0)

	# 굽기 진행 메시지 (화면 하단 가운데)
	if is_instance_valid(_cook_msg_lbl):
		_cook_msg_lbl.text = str(loot.cook_msg)
		_cook_msg_lbl.size = Vector2(size.x, 24.0)
		_cook_msg_lbl.position = Vector2(0.0, size.y - 130.0)

	# 상함 알림 페이드
	if _alert_t > 0.0:
		_alert_t -= delta
		_alert_lbl.modulate.a = clampf(_alert_t / 0.7, 0.0, 1.0)
		_alert_lbl.size = Vector2(size.x, 24.0)
		_alert_lbl.position = Vector2(0.0, size.y - 170.0)
		if _alert_t <= 0.0:
			_alert_lbl.text = ""


# Main 이 호출 — 먹기 버튼 탭이면 먹고 true (조이스틱보다 먼저 검사)
func try_eat(pos: Vector2) -> bool:
	if _eat_rect.has_point(pos):
		if loot:
			loot.eat_cooked_meat()
		return true
	return false


# 상함/알림 텍스트 (mino1 _showMeatAlert) — 잠깐 표시
func show_alert(msg: String) -> void:
	if is_instance_valid(_alert_lbl):
		_alert_lbl.text = msg
		_alert_t = 2.2   # mino1: delay 0.7 + 1.5 페이드


func _mk(txt: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	if kfont:
		l.add_theme_font_override("font", kfont)
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.text = txt
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _make_draw_script() -> GDScript:
	var src := """
extends Node2D
var hud
func _draw():
	if hud == null or hud.loot == null:
		return
	var eb = hud._eat_rect
	var loot = hud.loot
	# ── 고기 상태 패널 (먹기 버튼 위) ──
	var panel = Rect2(eb.position.x, eb.position.y - 50.0 - 6.0, 120.0, 50.0)
	draw_rect(panel, Color(0.039, 0.059, 0.027, 0.72), true)
	_outline(panel, Color(0.29, 0.227, 0.118, 0.9), 1.5)
	# 날고기 아이콘 (작은 빨강 타원)
	_ellipse(panel.position.x + 16, panel.position.y + 14, 9, 6, Color(0.8, 0.2, 0.2))
	# 구운고기 아이콘 (작은 갈색 타원)
	_ellipse(panel.position.x + 16, panel.position.y + 34, 9, 6, Color(0.545, 0.271, 0.075))

	# ── 먹기 버튼 ──
	var has_meat = loot.cooked_meat > 0
	var glow = Color(1.0, 0.533, 0.0, 0.7) if has_meat else Color(0.27, 0.27, 0.27, 0.2)
	_outline(Rect2(eb.position.x - 2, eb.position.y - 2, eb.size.x + 4, eb.size.y + 4), glow, 3.0)
	draw_rect(eb, Color(0.227, 0.102, 0.0, 0.92) if has_meat else Color(0.067, 0.067, 0.067, 0.92), true)
	_outline(eb, Color(1.0, 0.533, 0.0) if has_meat else Color(0.2, 0.2, 0.2), 2.0)
	# 버튼 안 구운고기 아이콘 (큰 버전)
	var bcx = eb.position.x + eb.size.x / 2.0
	var bcy = eb.position.y + eb.size.y / 2.0 - 2.0
	_ellipse(bcx, bcy, 14, 9, Color(0.545, 0.271, 0.075) if has_meat else Color(0.27, 0.27, 0.27))
	if has_meat:
		_ellipse(bcx - 4, bcy - 3, 6, 4, Color(1.0, 0.8, 0.533, 0.45))
		draw_line(Vector2(bcx - 8, bcy - 4), Vector2(bcx + 8, bcy + 2), Color(0.165, 0.063, 0.0, 0.8), 2.0)
		draw_circle(Vector2(bcx + 12, bcy - 4), 3.0, Color(1, 1, 1, 0.8))

func _ellipse(cx, cy, rx, ry, col):
	var pts = PackedVector2Array()
	for i in 18:
		var a = TAU * float(i) / 18.0
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	draw_colored_polygon(pts, col)

func _outline(r, col, w):
	var pts = PackedVector2Array([
		r.position, Vector2(r.position.x + r.size.x, r.position.y),
		Vector2(r.position.x + r.size.x, r.position.y + r.size.y),
		Vector2(r.position.x, r.position.y + r.size.y), r.position])
	draw_polyline(pts, col, w, true)
"""
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s
