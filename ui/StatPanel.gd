extends Control
class_name StatPanel
## StatPanel — 스탯 7종 분배창 + 골드→포인트 환전. mino1 _drawStatBtn/_drawStatPanel/_handleStatTap 대응.
## 우상단의 'STAT' 토글 버튼을 누르면 패널이 열린다. 포인트 있으면 버튼이 주황으로 빛난다.
## 7종: 공격력·공격속도·방어·최대HP·최대MP·이동속도·경험치획득. 골드 100 = 포인트 1 환전.
## 밸런스 증가값은 mino1 그대로 보존.

var main: Node = null
var kfont: Font = null

var open := false

# STAT 토글 버튼 (우상단)
var _btn_rect := Rect2(0, 0, 64, 44)
# 패널 내부 히트박스
var _close_rect := Rect2()
var _gold_buy_rect := Rect2()
var _stat_btn_rects: Array = []   # [{key, rect}]

var _draw_node: Node2D
var _labels: Array = []

# 스탯 정의 (mino1 statDefs 순서·증가값 보존)
const STAT_DEFS := [
	{"key": "atkPow",   "label": "공격력",     "unit": "+2/pt",    "icon": "⚔"},
	{"key": "atkSpeed", "label": "공격속도",   "unit": "빨라짐",   "icon": "⚡"},
	{"key": "armor",    "label": "방어",       "unit": "+1/pt",    "icon": "🛡"},
	{"key": "maxhp",    "label": "최대 HP",    "unit": "+18/pt",   "icon": "❤"},
	{"key": "maxmp",    "label": "최대 MP",    "unit": "+20/pt",   "icon": "💧"},
	{"key": "sp",       "label": "이동속도",   "unit": "+9/pt",    "icon": "💨"},
	{"key": "xpGain",   "label": "경험치획득", "unit": "+10%/pt",  "icon": "✨"},
]


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	# 닫혀 있을 땐 입력을 통과시킨다(IGNORE) — 안 그러면 화면 전체를 덮은 이 컨트롤이
	# 빈 곳 터치까지 다 먹어 이동·공격이 막힌다. 열릴 때만 STOP(모달)로 바꾼다.
	# 닫힘 상태의 STAT 토글 버튼은 Main._handle_touch 가 try_button() 으로 잡는다.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if main and main.has_method("get_kfont"):
		kfont = main.get_kfont()
	# 토글 버튼: 우상단 (퀘스트 텍스트 아래)
	_btn_rect = Rect2(size.x - 76.0, 56.0, 64.0, 44.0)

	_draw_node = Node2D.new()
	_draw_node.set_script(_make_draw_script())
	_draw_node.set("panel", self)
	add_child(_draw_node)
	gui_input.connect(_on_input)


func _process(_delta: float) -> void:
	# 버튼 위치는 화면 폭에 맞춰 갱신
	_btn_rect = Rect2(size.x - 76.0, 56.0, 64.0, 44.0)
	if open:
		_update_panel_labels()
	_draw_node.queue_redraw()


func _on_input(event: InputEvent) -> void:
	var pos := Vector2.ZERO
	var pressed := false
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position; pressed = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pos = event.position; pressed = true
	if not pressed:
		return

	if not open:
		# 닫혀 있을 땐 STAT 버튼만 반응
		if _btn_rect.has_point(pos):
			_open()
			accept_event()
		return

	# 열려 있을 때: 패널 내부 탭 처리 (mino1 _handleStatTap)
	_handle_tap(pos)
	accept_event()


func _open() -> void:
	open = true
	mouse_filter = Control.MOUSE_FILTER_STOP   # 열리면 모달(뒤로 입력 안 샘)
	_build_panel()


func _close() -> void:
	open = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 닫히면 입력 통과(이동·공격 살림)
	_clear_labels()
	_stat_btn_rects = []
	_draw_node.queue_redraw()


# 닫힘 상태의 STAT 토글 버튼을 Main._handle_touch 가 먼저 검사한다.
# (열려 있을 땐 STOP 모달이라 gui_input(_on_input)이 직접 처리하므로 여긴 안 탄다.)
func try_button(pos: Vector2) -> bool:
	if open:
		return false
	if _btn_rect.has_point(pos):
		_open()
		return true
	return false


# mino1 _drawStatPanel — 패널 레이아웃 계산 + 라벨 생성
func _build_panel() -> void:
	_clear_labels()
	_stat_btn_rects = []
	var p: Dictionary = GameState.player

	var w := size.x
	var h := size.y
	var panel_w := minf(w * 0.88, 560.0)
	var panel_h := 600.0       # 7종 + 환전 버튼
	var px := (w - panel_w) / 2.0
	var py := (h - panel_h) / 2.0
	_panel_px = px; _panel_py = py; _panel_pw = panel_w; _panel_ph = panel_h

	# 제목 / 닫기
	_mk("스탯 분배", 26, Color8(0x88, 0xaa, 0xff)).position = Vector2(px + 20.0, py + 16.0)
	var close_lbl := _mk("✕ 닫기", 22, Color8(0x88, 0xaa, 0xff))
	close_lbl.position = Vector2(px + panel_w - 110.0, py + 16.0)
	_close_rect = Rect2(px + panel_w - 116.0, py + 14.0, 104.0, 38.0)

	# 포인트 / 골드
	_pts_lbl = _mk("", 22, Color8(0xff, 0xaa, 0x44))
	_pts_lbl.position = Vector2(px + 20.0, py + 56.0)
	_gold_top_lbl = _mk("", 22, Color8(0xff, 0xd2, 0x4a))
	_gold_top_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gold_top_lbl.size = Vector2(160, 28)
	_gold_top_lbl.position = Vector2(px + panel_w - 180.0, py + 56.0)

	# 골드 → 포인트 환전 버튼
	var gb_x := px + 16.0
	var gb_y := py + 92.0
	var gb_w := panel_w - 32.0
	var gb_h := 42.0
	_gold_buy_rect = Rect2(gb_x, gb_y, gb_w, gb_h)
	_buy_lbl = _mk("💰 골드 100 → 포인트 +1", 20, Color8(0xff, 0xd2, 0x4a))
	_buy_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_buy_lbl.size = Vector2(gb_w, 28)
	_buy_lbl.position = Vector2(gb_x, gb_y + 8.0)

	# 7종 행
	var row_h := 58.0
	var start_y := py + 150.0
	var btn_w := 60.0
	var btn_h := 46.0
	_row_labels = []
	for i in range(STAT_DEFS.size()):
		var sd: Dictionary = STAT_DEFS[i]
		var row_y := start_y + i * row_h
		# 아이콘+라벨
		var lbl := _mk(str(sd["label"]), 18, Color8(0xaa, 0xbb, 0xdd))
		lbl.position = Vector2(px + 24.0, row_y + 14.0)
		# 현재값
		var val_lbl := _mk("", 20, Color.WHITE)
		val_lbl.position = Vector2(px + 24.0 + 170.0, row_y + 14.0)
		# 단위
		var unit_lbl := _mk(str(sd["unit"]), 14, Color8(0x66, 0x77, 0xaa))
		unit_lbl.position = Vector2(px + 24.0 + 250.0, row_y + 18.0)
		# + 버튼
		var btn_x := px + panel_w - btn_w - 18.0
		var btn_y := row_y + (row_h - 8.0 - btn_h) / 2.0
		var plus_lbl := _mk("+", 26, Color.WHITE)
		plus_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plus_lbl.size = Vector2(btn_w, btn_h)
		plus_lbl.position = Vector2(btn_x, btn_y + 6.0)
		_stat_btn_rects.append({"key": sd["key"], "rect": Rect2(btn_x, btn_y, btn_w, btn_h)})
		_row_labels.append({"val": val_lbl})

	_draw_node.queue_redraw()


var _panel_px := 0.0
var _panel_py := 0.0
var _panel_pw := 0.0
var _panel_ph := 0.0
var _pts_lbl: Label
var _gold_top_lbl: Label
var _buy_lbl: Label
var _row_labels: Array = []


func _update_panel_labels() -> void:
	var p: Dictionary = GameState.player
	var pts := int(p.get("statPoints", 0))
	var gold := int(p.get("gold", 0))
	if is_instance_valid(_pts_lbl):
		_pts_lbl.text = "포인트: %d" % pts
		_pts_lbl.add_theme_color_override("font_color", Color8(0xff, 0xaa, 0x44) if pts > 0 else Color8(0x88, 0x88, 0x88))
	if is_instance_valid(_gold_top_lbl):
		_gold_top_lbl.text = "G %d" % gold
	if is_instance_valid(_buy_lbl):
		var can_buy := gold >= 100
		_buy_lbl.add_theme_color_override("font_color", Color8(0xff, 0xd2, 0x4a) if can_buy else Color8(0x55, 0x66, 0x77))
	# 행 값 갱신
	for i in range(_row_labels.size()):
		if i >= STAT_DEFS.size():
			break
		var key: String = STAT_DEFS[i]["key"]
		var lbl: Label = _row_labels[i]["val"]
		if is_instance_valid(lbl):
			lbl.text = _stat_value_str(key, p)


func _stat_value_str(key: String, p: Dictionary) -> String:
	match key:
		"atkPow":
			return str(int(p.get("atkPow", 0)))
		"atkSpeed":
			var spd := float(p.get("atkSpeed", 0.5))
			return "%.1f/초" % (1.0 / spd if spd > 0.0 else 0.0)
		"armor":
			return str(int(p.get("armor", 0)))
		"maxhp":
			return str(int(p.get("maxhp", 0)))
		"maxmp":
			return str(int(p.get("maxmp", 0)))
		"sp":
			return str(int(round(float(p.get("sp", 0)))))
		"xpGain":
			return "%d%%" % int(round(float(p.get("xpGainMult", 1.0)) * 100.0))
	return ""


# mino1 _handleStatTap — 닫기 / 환전 / + 버튼
func _handle_tap(pos: Vector2) -> void:
	var p: Dictionary = GameState.player

	# 닫기 (또는 토글 버튼 다시 누름)
	if _close_rect.has_point(pos) or _btn_rect.has_point(pos):
		_close()
		return
	# 패널 밖을 누르면 닫는다(편의)
	var panel_rect := Rect2(_panel_px, _panel_py, _panel_pw, _panel_ph)
	if not panel_rect.has_point(pos):
		_close()
		return

	# 골드 → 포인트 환전 (골드 100)
	if _gold_buy_rect.has_point(pos):
		if int(p.get("gold", 0)) >= 100:
			p["gold"] = int(p["gold"]) - 100
			p["statPoints"] = int(p.get("statPoints", 0)) + 1
			GameState.save_game()
		return

	if int(p.get("statPoints", 0)) <= 0:
		return

	# + 버튼
	for btn in _stat_btn_rects:
		if (btn["rect"] as Rect2).has_point(pos):
			_apply_stat(btn["key"], p)
			return


# 스탯 1 적용 (mino1 _handleStatTap 의 증가값 그대로 보존)
func _apply_stat(key: String, p: Dictionary) -> void:
	p["statPoints"] = int(p["statPoints"]) - 1
	var spent: Dictionary = p.get("spentStats", {})
	match key:
		"atkPow":
			p["atkPow"] = float(p.get("atkPow", 0)) + 2.0
			spent["atkPow"] = int(spent.get("atkPow", 0)) + 2
		"armor":
			p["armor"] = float(p.get("armor", 0)) + 1.0
			spent["armor"] = int(spent.get("armor", 0)) + 1
		"maxhp":
			p["maxhp"] = float(p.get("maxhp", 0)) + 18.0
			p["hp"] = minf(float(p["maxhp"]), float(p.get("hp", 0)) + 18.0)
			spent["maxhp"] = int(spent.get("maxhp", 0)) + 18
		"maxmp":
			p["maxmp"] = float(p.get("maxmp", 0)) + 20.0
			p["mp"] = minf(float(p["maxmp"]), float(p.get("mp", 0)) + 20.0)
			spent["maxmp"] = int(spent.get("maxmp", 0)) + 20
		"sp":
			p["sp"] = minf(float(p.get("sp", 0)) + 9.0, 380.0)
			spent["sp"] = int(spent.get("sp", 0)) + 9
		"atkSpeed":
			# 공격 쿨다운 감소(=공속 증가). 0.12 미만으론 안 내려감.
			p["atkSpeed"] = maxf(0.12, snappedf(float(p.get("atkSpeed", 0.5)) - 0.03, 0.001))
			spent["atkSpeed"] = int(spent.get("atkSpeed", 0)) + 1
		"xpGain":
			p["xpGainMult"] = snappedf(float(p.get("xpGainMult", 1.0)) + 0.1, 0.01)
			spent["xpGain"] = int(spent.get("xpGain", 0)) + 1
	p["spentStats"] = spent
	GameState.save_game()


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
	_row_labels = []


# STAT 버튼 + 패널 배경을 그리는 Node2D
func _make_draw_script() -> GDScript:
	var src := """
extends Node2D
var panel
func _draw():
	if panel == null:
		return
	var p = GameState.player
	var has_pts = int(p.get('statPoints', 0)) > 0
	# ── STAT 토글 버튼 ──
	var b = panel._btn_rect
	var bcol = Color(0.227, 0.125, 0.063, 0.92) if has_pts else (Color(0.102, 0.063, 0.251, 0.92) if panel.open else Color(0.078, 0.078, 0.157, 0.92))
	draw_rect(b, bcol, true)
	var ecol = Color(1.0, 0.533, 0.267) if has_pts else (Color(1.0, 0.933, 0.267) if panel.open else Color(0.533, 0.667, 1.0))
	_outline(b, ecol, 2.0)
	# 포인트 뱃지 (빨강 원 + 숫자는 라벨 없이 점으로 표시)
	if has_pts:
		draw_circle(Vector2(b.position.x + b.size.x - 6, b.position.y + 6), 9.0, Color(1.0, 0.267, 0.0))

	# ── 패널 ──
	if not panel.open:
		return
	var w = panel.size.x
	var h = panel.size.y
	draw_rect(Rect2(0, 0, w, h), Color(0.047, 0.059, 0.039, 0.92), true)
	var pr = Rect2(panel._panel_px, panel._panel_py, panel._panel_pw, panel._panel_ph)
	draw_rect(pr, Color(0.078, 0.078, 0.157, 1.0), true)
	_outline(pr, Color(0.533, 0.667, 1.0), 2.0)
	# 환전 버튼 배경
	var gold = int(p.get('gold', 0))
	var can_buy = gold >= 100
	var gb = panel._gold_buy_rect
	draw_rect(gb, Color(0.29, 0.227, 0.071, 1.0) if can_buy else Color(0.102, 0.102, 0.165, 1.0), true)
	_outline(gb, Color(0.867, 0.667, 0.2) if can_buy else Color(0.2, 0.2, 0.333), 2.0)
	# 7종 행 + + 버튼
	var idx = 0
	for btn in panel._stat_btn_rects:
		var r = btn['rect']
		# 행 배경 (행 전체 폭)
		var row_bg = Rect2(panel._panel_px + 12, r.position.y - 4, panel._panel_pw - 24, r.size.y + 8)
		draw_rect(row_bg, Color(0.11, 0.11, 0.22, 0.8) if idx % 2 == 0 else Color(0.094, 0.094, 0.188, 0.8), true)
		var has = int(p.get('statPoints', 0)) > 0
		draw_rect(r, Color(0.133, 0.267, 0.533, 1.0) if has else Color(0.102, 0.102, 0.165, 1.0), true)
		_outline(r, Color(0.533, 0.667, 1.0) if has else Color(0.2, 0.2, 0.333), 2.0)
		idx += 1

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
