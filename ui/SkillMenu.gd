extends Control
class_name SkillMenu
## SkillMenu — 전직(클래스) 스킬 메뉴 패널. mino1 _openSkillMenu/_closeSkillMenu 대응.
## 우하단 전직 스킬 버튼을 누르면 열린다. 현재 직업이 쓸 수 있는 클래스 스킬을 카드로 나열.
## 준비된(쿨0·마나충분) 카드를 탭하면 SkillSystem.cast_class_skill 로 발동 후 닫힌다.
## 카드 밖을 탭하면 그냥 닫힌다. 떠 있는 동안 게임은 일시정지.

var main: Node = null
var kfont: Font = null
var skills: Node = null

var active := false
var _card_rects: Array = []      # [{rect, def, ready}]
var _draw_node: Node2D
var _labels: Array = []


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	if main and main.has_method("get_kfont"):
		kfont = main.get_kfont()
	if main:
		skills = main.skills
	_draw_node = Node2D.new()
	_draw_node.set_script(_make_draw_script())
	_draw_node.set("panel", self)
	add_child(_draw_node)
	gui_input.connect(_on_input)


func open() -> void:
	if skills == null:
		return
	var list: Array = skills.my_class_skills()
	if list.is_empty():
		return
	active = true
	visible = true
	get_tree().paused = true
	_build(list)


func _build(list: Array) -> void:
	_clear_labels()
	_card_rects = []
	var p: Dictionary = GameState.player
	var w := size.x
	var h := size.y

	var title := _mk("✦ 전직 스킬", 26, Color8(0xff, 0xdd, 0x66))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(w, 36)
	title.position = Vector2(0, h * 0.14)

	var cw := minf(w * 0.84, 520.0)
	var ch := 100.0
	var gap := 16.0
	var sx := (w - cw) / 2.0
	var sy := h * 0.24
	for i in range(list.size()):
		var d: Dictionary = list[i]
		var cy := sy + i * (ch + gap)
		var cd_left := float(skills.ult_cd.get(d["key"], 0.0))
		var ready := cd_left <= 0.0 and float(p["mp"]) >= float(d["mp"])
		_card_rects.append({"rect": Rect2(sx, cy, cw, ch), "def": d, "ready": ready})
		var name_lbl := _mk("%s  %s" % [d["icon"], d["name"]], 22, Color.WHITE if ready else Color8(0x88, 0x88, 0x88))
		name_lbl.position = Vector2(sx + 20.0, cy + 14.0)
		var sub := ("쿨타임 %.1f초" % cd_left) if cd_left > 0.0 else ("마나 %d" % int(d["mp"]))
		var desc_lbl := _mk("%s · %s" % [d["desc"], sub], 15, Color8(0xcd, 0xd6, 0xe2) if ready else Color8(0x77, 0x77, 0x77))
		desc_lbl.position = Vector2(sx + 20.0, cy + 52.0)
		desc_lbl.size = Vector2(cw - 40.0, 30.0)

	var close_lbl := _mk("바깥을 탭하면 닫혀요", 15, Color8(0xaa, 0xaa, 0xaa))
	close_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_lbl.size = Vector2(w, 24)
	close_lbl.position = Vector2(0, sy + list.size() * (ch + gap) + 8.0)

	_draw_node.queue_redraw()


func _on_input(event: InputEvent) -> void:
	if not active:
		return
	var pos := Vector2.ZERO
	var pressed := false
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position; pressed = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pos = event.position; pressed = true
	if not pressed:
		return
	for card in _card_rects:
		if (card["rect"] as Rect2).has_point(pos):
			var ok: bool = skills.cast_class_skill(card["def"])
			if ok:
				_close()
			else:
				# 마나/쿨 부족 → 상태 갱신 재표시
				_build(skills.my_class_skills())
			return
	# 카드 밖 = 닫기
	_close()


func _close() -> void:
	active = false
	visible = false
	_clear_labels()
	_card_rects = []
	_draw_node.queue_redraw()
	get_tree().paused = false


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
	_labels.append(l)
	return l


func _clear_labels() -> void:
	for l in _labels:
		if is_instance_valid(l):
			l.queue_free()
	_labels = []


func _make_draw_script() -> GDScript:
	var src := """
extends Node2D
var panel
func _draw():
	if panel == null or not panel.active:
		return
	var w = panel.size.x
	var h = panel.size.y
	draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.82), true)
	for card in panel._card_rects:
		var r = card['rect']
		var ready = card['ready']
		var col = card['def']['color']
		draw_rect(r, Color(0.078, 0.078, 0.149, 1.0) if ready else Color(0.047, 0.047, 0.063, 1.0), true)
		var pts = PackedVector2Array([
			r.position, Vector2(r.position.x + r.size.x, r.position.y),
			Vector2(r.position.x + r.size.x, r.position.y + r.size.y),
			Vector2(r.position.x, r.position.y + r.size.y), r.position])
		draw_polyline(pts, col if ready else Color(0.333, 0.333, 0.333), 2.5, true)
"""
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s
