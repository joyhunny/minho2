extends Control
class_name DifficultyPanel
## DifficultyPanel — 난이도 선택창. mino1 _showDifficultySelect / _pickDifficulty 대응.
## 10단계(DIFFICULTY_DEFS)를 2열 그리드로. 고르면 GameState.difficulty 에 저장하고 닫는다.
## 첫 실행(난이도 미선택)에 자동으로 뜨고, 우상단 ↻ 버튼으로 언제든 다시 부를 수 있다.
## 떠 있는 동안 게임 일시정지(get_tree().paused). 밸런스(난이도 배율)는 GameData 가 정본.

var main: Node = null
var kfont: Font = null

var active := false
var _btn_rects: Array = []     # [{rect, idx}]
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
	_btn_rects = []
	var w := size.x
	var h := size.y

	var title := _mk("난이도 선택", 28, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(w, 36)
	title.position = Vector2(0, h * 0.07)
	var sub := _mk("쉬울수록 느긋, 어려울수록 가만히 있으면 죽는다", 14, Color8(0xa9, 0xa9, 0xc4))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.size = Vector2(w, 22)
	sub.position = Vector2(0, h * 0.07 + 36.0)

	# 2열 × 5행 그리드 (가운데 정렬·최대폭 제한)
	var defs: Array = GameData.DIFFICULTY_DEFS
	var cols := 2
	var gap := 12.0
	var grid_w := minf(w - 40.0, 480.0)
	var grid_x := (w - grid_w) / 2.0
	var cell_w := (grid_w - gap * (cols - 1)) / cols
	var cell_h := minf(86.0, (h * 0.66) / 5.0 - gap)
	var top := h * 0.07 + 80.0

	for i in range(defs.size()):
		var d: Dictionary = defs[i]
		var col := i % cols
		var row := i / cols
		var x := grid_x + col * (cell_w + gap)
		var y := top + row * (cell_h + gap)
		_btn_rects.append({"rect": Rect2(x, y, cell_w, cell_h), "idx": i})
		var nm := _mk(str(d["name"]), 20, Color.WHITE)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.size = Vector2(cell_w, 26)
		nm.position = Vector2(x, y + cell_h * 0.22)
		var sb := _mk(str(d["sub"]), 13, Color8(0xe6, 0xe6, 0xf0))
		sb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sb.size = Vector2(cell_w, 20)
		sb.position = Vector2(x, y + cell_h * 0.6)

	var hint := _mk("우상단 ↻ 버튼으로 언제든 처음부터 다시 고를 수 있어", 12, Color8(0x7e, 0x7e, 0xa0))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size = Vector2(w, 20)
	hint.position = Vector2(0, top + 5.0 * (cell_h + gap) + 8.0)

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
	for b in _btn_rects:
		if (b["rect"] as Rect2).has_point(pos):
			_pick(int(b["idx"]))
			return


func _pick(idx: int) -> void:
	GameState.difficulty = idx
	GameState.save_game()
	_close()


func _close() -> void:
	active = false
	visible = false
	get_tree().paused = false
	_clear_labels()
	_btn_rects = []
	# 난이도 직후엔 세계 지도로 (mino1 은 인트로 → 게임, minho2 는 바로 지도/전투)
	if main and main.has_method("on_difficulty_picked"):
		main.on_difficulty_picked()


func _mk(txt: String, sz: int, col: Color) -> Label:
	var l := Label.new()
	if kfont:
		l.add_theme_font_override("font", kfont)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
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


# 패널 배경·버튼 칸을 그리는 Node2D 스크립트
func _make_draw_script() -> GDScript:
	var src := """
extends Node2D
var panel
func _draw():
	if panel == null or not panel.active:
		return
	var vp = get_viewport().get_visible_rect().size
	# 어두운 전체 오버레이
	draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.04, 0.04, 0.08, 0.94), true)
	# 버튼 칸 (난이도 색)
	var defs = GameData.DIFFICULTY_DEFS
	for b in panel._btn_rects:
		var r = b['rect']
		var d = defs[b['idx']]
		var c = d['color']
		draw_rect(r, Color(c.r, c.g, c.b, 0.28), true)
		draw_rect(r, Color(c.r, c.g, c.b, 0.95), false, 2.0)
"""
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s
