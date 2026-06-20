extends Control
class_name InventoryPanel
## InventoryPanel — 가방 버튼(우상단) + 장비 창. mino1 _drawInvBtn/_drawInventoryPanel/_handleInvTap 대응.
## 장착 슬롯 3개(무기·갑옷·장신구) + 4×4 인벤 그리드 + 판매 + 해제 + 장착.
## 장착/해제/판매는 모두 InventorySystem(main.inventory)을 통해서만 한다(단일 권한).
## 패널이 열리면 게임 일시정지(레벨업창과 달리 mino1 은 안 멈췄으나, Godot 세로 모바일에선 탭 안정 위해 멈춤).

var main: Node = null
var kfont: Font = null
var inv: Node = null            # InventorySystem

var open := false
var selected_idx := -1          # 인벤 선택 인덱스 (-1=없음) (mino1 _invSelectedIdx)

# 가방 토글 버튼 (우상단)
var _btn_rect := Rect2(0, 0, 64, 44)

# 패널 히트박스
var _panel_rect := Rect2()
var _close_rect := Rect2()
var _slot_rects: Array = []     # [{slot, rect}]
var _cell_rects: Array = []     # [{i, rect}]
var _sell_rect := Rect2()
var _sell_idx := -1
var _newgame_rect := Rect2()

var _draw_node: Node2D
var _labels: Array = []

const SLOT_KEYS := ["weapon", "armor", "accessory"]
const SLOT_LABELS := ["무기", "갑옷", "장신구"]


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	if main and main.has_method("get_kfont"):
		kfont = main.get_kfont()
	if main:
		inv = main.inventory
	_btn_rect = Rect2(size.x - 76.0, 4.0, 64.0, 44.0)
	_draw_node = Node2D.new()
	_draw_node.set_script(_make_draw_script())
	_draw_node.set("panel", self)
	add_child(_draw_node)
	gui_input.connect(_on_input)


func _process(_delta: float) -> void:
	_btn_rect = Rect2(size.x - 76.0, 4.0, 64.0, 44.0)
	if open:
		_update_labels()
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
		# 닫혀 있을 땐 가방 버튼만 반응 (안 누르면 입력 통과)
		if _btn_rect.has_point(pos):
			_open()
			accept_event()
		return

	_handle_tap(pos)
	accept_event()


func _open() -> void:
	open = true
	selected_idx = -1
	get_tree().paused = true
	_build()


func _close() -> void:
	open = false
	selected_idx = -1
	get_tree().paused = false
	_clear_labels()
	_slot_rects = []
	_cell_rects = []
	_draw_node.queue_redraw()


# mino1 _drawInventoryPanel — 레이아웃 계산 + 라벨 생성 (값 갱신은 _update_labels)
func _build() -> void:
	_clear_labels()
	_slot_rects = []
	_cell_rects = []
	var p: Dictionary = GameState.player
	var w := size.x
	var h := size.y
	var panel_w := minf(w * 0.94, 660.0)
	var panel_h := minf(h * 0.82, 720.0)
	var px := (w - panel_w) / 2.0
	var py := (h - panel_h) / 2.0
	_panel_rect = Rect2(px, py, panel_w, panel_h)

	# 제목 / 닫기
	_mk("장비 창", 26, Color8(0xff, 0xcf, 0x5c)).position = Vector2(px + 20.0, py + 14.0)
	var close_lbl := _mk("✕ 닫기", 22, Color8(0xff, 0xcf, 0x5c))
	close_lbl.position = Vector2(px + panel_w - 110.0, py + 14.0)
	_close_rect = Rect2(px + panel_w - 116.0, py + 12.0, 104.0, 40.0)

	# 장착 슬롯 3개 (좌측)
	var slot_w := 200.0
	var slot_h := 80.0
	for i in range(SLOT_KEYS.size()):
		var slot: String = SLOT_KEYS[i]
		var sx := px + 20.0
		var sy := py + 70.0 + i * (slot_h + 16.0)
		_slot_rects.append({"slot": slot, "rect": Rect2(sx, sy, slot_w, slot_h)})
		_mk(SLOT_LABELS[i], 14, Color8(0xaa, 0xaa, 0xaa)).position = Vector2(sx + 10.0, sy + 8.0)
		# 슬롯 내용 라벨 (값은 _update_labels 에서)
		var content := _mk("", 16, Color.WHITE)
		content.position = Vector2(sx + 10.0, sy + 36.0)
		content.size = Vector2(slot_w - 20.0, 24.0)
		_slot_rects[i]["content_lbl"] = content

	# 스탯 요약 (슬롯 아래)
	var stat_y := py + 70.0 + 3.0 * (slot_h + 16.0)
	_stat_lbl = _mk("", 15, Color8(0x8f, 0xb0, 0x8f))
	_stat_lbl.position = Vector2(px + 20.0, stat_y)
	_stat_lbl.size = Vector2(slot_w + 20.0, 90.0)

	# 인벤 그리드 4×4 (우측)
	var cols := 4
	var cell := 64.0
	var gap := 10.0
	var gx := px + 250.0
	var gy := py + 60.0
	for i in range(InventorySystem.INV_MAX):
		var c := i % cols
		var r := i / cols
		var cx := gx + c * (cell + gap)
		var cy := gy + r * (cell + gap)
		_cell_rects.append({"i": i, "rect": Rect2(cx, cy, cell, cell)})
		var name_lbl := _mk("", 11, Color.WHITE)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.size = Vector2(cell, cell)
		name_lbl.position = Vector2(cx, cy)
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_cell_rects[i]["name_lbl"] = name_lbl

	# 용량 표시
	_cap_lbl = _mk("", 13, Color8(0x8f, 0xb0, 0x8f))
	_cap_lbl.position = Vector2(gx, py + panel_h - 30.0)

	# 처음부터 버튼 (좌하단, 작게)
	var nb_w := 100.0
	var nb_h := 32.0
	var nb_x := px + 20.0
	var nb_y := py + panel_h - 44.0
	_newgame_rect = Rect2(nb_x, nb_y, nb_w, nb_h)
	var ng_lbl := _mk("처음부터", 14, Color8(0xff, 0xaa, 0xaa))
	ng_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ng_lbl.size = Vector2(nb_w, nb_h)
	ng_lbl.position = Vector2(nb_x, nb_y + 6.0)

	# 판매 버튼 (선택 시) — 라벨은 _update_labels 에서 표시/숨김
	_sell_name_lbl = _mk("", 13, Color.WHITE)
	_sell_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sell_name_lbl.size = Vector2(150.0, 18.0)
	_sell_lbl = _mk("", 16, Color8(0xff, 0xdd, 0x44))
	_sell_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sell_lbl.size = Vector2(150.0, 36.0)

	_update_labels()
	_draw_node.queue_redraw()


var _stat_lbl: Label
var _cap_lbl: Label
var _sell_lbl: Label
var _sell_name_lbl: Label


# 값 갱신 (장착 내용·인벤·스탯·판매 버튼) (mino1 텍스트 재생성 대응)
func _update_labels() -> void:
	var p: Dictionary = GameState.player
	var equip_d: Dictionary = p.get("equip", {})

	# 장착 슬롯 내용
	for sr in _slot_rects:
		var lbl: Label = sr.get("content_lbl", null)
		if not is_instance_valid(lbl):
			continue
		var item_id = equip_d.get(sr["slot"], null)
		if item_id != null and GameData.ITEM_DEFS.has(str(item_id)):
			var rarity := int(GameData.ITEM_DEFS[str(item_id)].get("rarity", 0))
			lbl.text = str(GameData.ITEM_DEFS[str(item_id)].get("name", ""))
			lbl.add_theme_color_override("font_color", GameData.RARITY_TABLE[rarity]["color"])
		else:
			lbl.text = "(없음)"
			lbl.add_theme_color_override("font_color", Color8(0x55, 0x55, 0x55))

	# 스탯 요약
	if is_instance_valid(_stat_lbl):
		_stat_lbl.text = "공격력: %d\n방어력: %d\n이동속도: %d" % [
			int(p.get("atkPow", 0)), int(p.get("armor", 0)), int(round(float(p.get("sp", 0))))]

	# 인벤 칸 이름
	var bag: Array = GameState.inventory
	for cr in _cell_rects:
		var lbl: Label = cr.get("name_lbl", null)
		if not is_instance_valid(lbl):
			continue
		var i: int = cr["i"]
		if i < bag.size():
			var item_id := str(bag[i].get("item_id", ""))
			if GameData.ITEM_DEFS.has(item_id):
				var rarity := int(GameData.ITEM_DEFS[item_id].get("rarity", 0))
				lbl.text = str(GameData.ITEM_DEFS[item_id].get("name", "")).substr(0, 5)
				lbl.add_theme_color_override("font_color", GameData.RARITY_TABLE[rarity]["color"])
			else:
				lbl.text = ""
		else:
			lbl.text = ""

	# 용량
	if is_instance_valid(_cap_lbl):
		_cap_lbl.text = "%d/%d" % [bag.size(), InventorySystem.INV_MAX]

	# 판매 버튼 (선택된 인벤 칸이 있을 때)
	_sell_rect = Rect2()
	_sell_idx = -1
	if selected_idx >= 0 and selected_idx < bag.size():
		var sel_id := str(bag[selected_idx].get("item_id", ""))
		if GameData.ITEM_DEFS.has(sel_id):
			var price: int = inv.sell_price(sel_id) if inv else 0
			var rarity := int(GameData.ITEM_DEFS[sel_id].get("rarity", 0))
			var sell_w := 150.0
			var sell_h := 40.0
			var sx := _panel_rect.position.x + _panel_rect.size.x - sell_w - 20.0
			var sy := _panel_rect.position.y + _panel_rect.size.y - sell_h - 12.0
			_sell_rect = Rect2(sx, sy, sell_w, sell_h)
			_sell_idx = selected_idx
			if is_instance_valid(_sell_name_lbl):
				_sell_name_lbl.text = str(GameData.ITEM_DEFS[sel_id].get("name", ""))
				_sell_name_lbl.add_theme_color_override("font_color", GameData.RARITY_TABLE[rarity]["color"])
				_sell_name_lbl.position = Vector2(sx, sy - 20.0)
				_sell_name_lbl.visible = true
			if is_instance_valid(_sell_lbl):
				_sell_lbl.text = "팔기  +%dG" % price
				_sell_lbl.position = Vector2(sx, sy + 8.0)
				_sell_lbl.visible = true
	else:
		if is_instance_valid(_sell_name_lbl):
			_sell_name_lbl.visible = false
		if is_instance_valid(_sell_lbl):
			_sell_lbl.visible = false


# mino1 _handleInvTap — 닫기 / 처음부터 / 판매 / 해제 / 장착
func _handle_tap(pos: Vector2) -> void:
	var p: Dictionary = GameState.player

	# 닫기 (또는 가방 버튼 다시 누름)
	if _close_rect.has_point(pos) or _btn_rect.has_point(pos):
		_close()
		return
	# 패널 밖을 누르면 닫는다(편의)
	if not _panel_rect.has_point(pos):
		_close()
		return

	# 처음부터 버튼
	if _newgame_rect.has_point(pos):
		_close()
		_new_game()
		return

	# 판매 버튼
	if _sell_rect.size.x > 0.0 and _sell_rect.has_point(pos) and _sell_idx >= 0:
		var price: int = inv.sell(_sell_idx) if inv else 0
		if price > 0 and main:
			main.show_pickup_toast("판매! +%dG" % price)
		selected_idx = -1
		_update_labels()
		_draw_node.queue_redraw()
		return

	# 장착 슬롯 탭 → 해제 (가방으로)
	for sr in _slot_rects:
		if (sr["rect"] as Rect2).has_point(pos):
			var equip_d: Dictionary = p.get("equip", {})
			var prev = equip_d.get(sr["slot"], null)
			if prev != null and inv:
				if not inv.bag_full():
					inv.unequip(sr["slot"])
					inv.add_to_bag(str(prev))
					selected_idx = -1
					GameState.save_game()
					_update_labels()
					_draw_node.queue_redraw()
				elif main:
					main.show_pickup_toast("가방이 가득 찼다!")
			return

	# 인벤 칸 탭
	var bag: Array = GameState.inventory
	for cr in _cell_rects:
		if (cr["rect"] as Rect2).has_point(pos):
			var i: int = cr["i"]
			if i < bag.size():
				if selected_idx == i:
					# 이미 선택된 칸 다시 탭 → 장착 (교체된 이전 건 가방으로)
					var item_id := str(bag[i].get("item_id", ""))
					var slot := str(GameData.ITEM_DEFS[item_id].get("slot", "weapon"))
					bag.remove_at(i)
					var prev: String = inv.equip(slot, item_id) if inv else ""
					if prev != "":
						inv.add_to_bag(prev)
					selected_idx = -1
					GameState.save_game()
				else:
					# 첫 탭 → 선택 (판매 버튼 표시)
					selected_idx = i
				_update_labels()
				_draw_node.queue_redraw()
			return


# 처음부터: 저장 지우고 새 게임 → 씬 재시작 (mino1 _newGame)
func _new_game() -> void:
	GameState.new_game(GameState.difficulty if GameState.difficulty >= 0 else 1)
	get_tree().paused = false
	get_tree().reload_current_scene()


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
	if panel == null:
		return
	# ── 가방 토글 버튼 ──
	var b = panel._btn_rect
	var bag_full = GameState.inventory.size() >= 16
	var bcol = Color(0.227, 0.188, 0.063, 0.92) if panel.open else Color(0.102, 0.141, 0.078, 0.92)
	draw_rect(b, bcol, true)
	var ecol = Color(1.0, 0.933, 0.267) if panel.open else Color(1.0, 0.812, 0.361)
	_outline(b, ecol, 2.0)
	_draw_bag_icon(b.position.x + b.size.x / 2.0, b.position.y + b.size.y / 2.0 + 2.0)
	# 가득 찼으면 빨강 점
	if bag_full:
		draw_circle(Vector2(b.position.x + b.size.x - 6, b.position.y + 6), 8.0, Color(0.9, 0.25, 0.2))

	if not panel.open:
		return
	var w = panel.size.x
	var h = panel.size.y
	# 오버레이
	draw_rect(Rect2(0, 0, w, h), Color(0.047, 0.059, 0.039, 0.92), true)
	# 패널 배경
	var pr = panel._panel_rect
	draw_rect(pr, Color(0.102, 0.133, 0.078, 1.0), true)
	_outline(pr, Color(1.0, 0.812, 0.361), 2.0)

	var p = GameState.player
	var equip_d = p.get('equip', {})
	# 장착 슬롯
	for sr in panel._slot_rects:
		var r = sr['rect']
		var item_id = equip_d.get(sr['slot'], null)
		var border = Color(0.27, 0.27, 0.27)
		if item_id != null and GameData.ITEM_DEFS.has(str(item_id)):
			var rarity = int(GameData.ITEM_DEFS[str(item_id)].get('rarity', 0))
			border = GameData.RARITY_TABLE[rarity]['border']
		draw_rect(r, Color(0.067, 0.067, 0.067, 1.0), true)
		_outline(r, border, 2.0)
	# 인벤 칸
	var bag = GameState.inventory
	for cr in panel._cell_rects:
		var r = cr['rect']
		var i = cr['i']
		if i < bag.size():
			var item_id = str(bag[i].get('item_id', ''))
			var border = Color(0.27, 0.27, 0.27)
			if GameData.ITEM_DEFS.has(item_id):
				var rarity = int(GameData.ITEM_DEFS[item_id].get('rarity', 0))
				border = GameData.RARITY_TABLE[rarity]['border']
			draw_rect(r, Color(0.118, 0.165, 0.094, 1.0), true)
			_outline(r, border, 1.5)
			if i == panel.selected_idx:
				var sr = Rect2(r.position.x - 2, r.position.y - 2, r.size.x + 4, r.size.y + 4)
				_outline(sr, Color(1.0, 0.867, 0.133), 3.0)
		else:
			draw_rect(r, Color(0.067, 0.067, 0.067, 1.0), true)
			_outline(r, Color(0.2, 0.2, 0.2), 1.0)
	# 처음부터 버튼
	var ng = panel._newgame_rect
	draw_rect(ng, Color(0.353, 0.102, 0.102, 1.0), true)
	_outline(ng, Color(0.8, 0.267, 0.267, 0.8), 1.5)
	# 판매 버튼
	var sv = panel._sell_rect
	if sv.size.x > 0.0:
		draw_rect(sv, Color(0.102, 0.29, 0.102, 1.0), true)
		_outline(sv, Color(0.267, 0.8, 0.267, 0.9), 2.0)

func _draw_bag_icon(cx, cy):
	# 가방 몸통
	draw_rect(Rect2(cx - 9, cy - 6, 18, 14), Color(0.784, 0.627, 0.376), true)
	draw_rect(Rect2(cx - 7, cy - 5, 10, 5), Color(1.0, 0.8, 0.533, 0.5), true)
	_outline(Rect2(cx - 9, cy - 6, 18, 14), Color(0.478, 0.353, 0.125, 0.9), 1.5)
	# 손잡이 (위쪽 반원)
	draw_arc(Vector2(cx, cy - 8), 5.0, PI, TAU, 12, Color(0.69, 0.5, 0.25), 2.5)
	# 버클
	draw_rect(Rect2(cx - 3, cy - 1, 6, 4), Color(1.0, 0.867, 0.533), true)

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
