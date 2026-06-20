extends Control
class_name WorldMapPanel
## WorldMapPanel — 세계 지도(지역 해금·선택). mino1 _showWorldMap / _handleWorldMapTap / _enterRegion 대응.
## 4지역(REGION_DEFS) 카드를 세로로 잇고, 깬 지역만 열린다(✅ 클리어 / ▶ 입장가능 / 🔒 잠김).
## 열린 카드를 탭하면 그 지역으로 입장 → Main.enter_region(idx) 가 지형·적·보스를 리셋한다.
## 떠 있는 동안 게임 일시정지. 보스를 깨면 다음 지역이 해금되고 이 지도가 다시 뜬다.

var main: Node = null
var kfont: Font = null

var active := false
var _card_rects: Array = []    # [{rect, idx, unlocked}]
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
	_draw_node = Node2D.new()
	_draw_node.set_script(_make_draw_script())
	_draw_node.set("panel", self)
	add_child(_draw_node)
	gui_input.connect(_on_input)


func open() -> void:
	if active:
		return
	active = true
	visible = true
	get_tree().paused = true
	_build()


func _build() -> void:
	_clear_labels()
	_card_rects = []
	var w := size.x
	var h := size.y
	var defs: Array = GameData.REGION_DEFS

	var title := _mk("🗺️ 세계 지도", 26, Color8(0xff, 0xe9, 0xa8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(w, 34)
	title.position = Vector2(0, h * 0.06)
	var sub := _mk("갈 곳을 골라라 — 깬 지역만 열려 있다", 13, Color8(0x9f, 0xc0, 0xa8))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.size = Vector2(w, 22)
	sub.position = Vector2(0, h * 0.06 + 34.0)

	var n := defs.size()
	var card_w := minf(w * 0.84, 480.0)
	var card_h := 88.0
	var gap := 16.0
	var start_y := h * 0.18
	var sx := (w - card_w) / 2.0
	var max_r := GameState.max_region
	var cur_r := GameState.region

	for i in range(n):
		var def: Dictionary = defs[i]
		var cy := start_y + i * (card_h + gap)
		var unlocked := i <= max_r
		var cleared := i < max_r
		_card_rects.append({"rect": Rect2(sx, cy, card_w, card_h), "idx": i, "unlocked": unlocked})
		var tag := "✅" if cleared else ("▶" if unlocked else "🔒")
		var here := "   · 지금 여기" if (i == cur_r and unlocked) else ""
		var name_col := Color8(0xff, 0xe9, 0xa8) if unlocked else Color8(0x77, 0x77, 0x77)
		var nm := _mk("%s %s %s%s" % [tag, def.get("icon", ""), def.get("name", ""), here], 18, name_col)
		nm.position = Vector2(sx + 18.0, cy + 16.0)
		nm.size = Vector2(card_w - 32.0, 24)
		var desc_col := Color8(0xa6, 0xc0, 0xa6) if unlocked else Color8(0x55, 0x55, 0x55)
		var desc_txt: String = def.get("desc", "") if unlocked else "아직 잠겨 있다 — 앞 지역을 깨면 열린다"
		var desc := _mk(desc_txt, 12, desc_col)
		desc.position = Vector2(sx + 18.0, cy + 50.0)
		desc.size = Vector2(card_w - 36.0, 30)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

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
	for c in _card_rects:
		if c["unlocked"] and (c["rect"] as Rect2).has_point(pos):
			_enter(int(c["idx"]))
			return


func _enter(idx: int) -> void:
	Audio.ui_tap()
	active = false
	visible = false
	get_tree().paused = false
	_clear_labels()
	_card_rects = []
	if main and main.has_method("enter_region"):
		main.enter_region(idx)


func _mk(txt: String, sz: int, col: Color) -> Label:
	var l := Label.new()
	if kfont:
		l.add_theme_font_override("font", kfont)
	l.add_theme_font_size_override("font_size", sz)
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


# 패널 배경·카드 칸·연결선을 그리는 Node2D 스크립트
func _make_draw_script() -> GDScript:
	var src := """
extends Node2D
var panel
func _draw():
	if panel == null or not panel.active:
		return
	var vp = get_viewport().get_visible_rect().size
	draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.03, 0.08, 0.06, 0.96), true)
	var defs = GameData.REGION_DEFS
	var prev_center = Vector2.ZERO
	var first = true
	for c in panel._card_rects:
		var r = c['rect']
		var def = defs[c['idx']]
		var unlocked = c['unlocked']
		# 연결선 (이전 카드와 잇기)
		if not first:
			var lc = Color(0.29, 0.42, 0.29) if unlocked else Color(0.16, 0.16, 0.16)
			draw_line(Vector2(r.position.x + 30, prev_center.y + r.size.y / 2.0), Vector2(r.position.x + 30, r.position.y), lc, 3.0)
		# 카드 배경
		var bg = Color(0.12, 0.16, 0.09) if unlocked else Color(0.08, 0.08, 0.08)
		draw_rect(r, bg, true)
		var border = def['panel_color'] if unlocked else Color(0.27, 0.27, 0.27)
		draw_rect(r, border, false, 2.5 if unlocked else 1.5)
		prev_center = r.position
		first = false
"""
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s
