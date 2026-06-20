extends Control
class_name LevelupPanel
## LevelupPanel — 레벨업 3택 스킬 선택창. mino1 _openLvlupPanel/_handleLvlupTap/_applySkill 대응.
## 한 번에 여러 레벨이 올라도 '하나씩' 큐로 처리한다(mino1 _pendingLvlups/_processLevelupQueue).
## 띄워 있는 동안 게임은 일시정지된다(get_tree().paused). Main 이 apply_skill 로 실제 효과를 건다.

var main: Node = null
var kfont: Font = null

var active := false
var pending := 0                  # 남은 레벨업(큐)
var _card_rects: Array = []       # [{rect, id}]
var _options: Array = []          # 이번에 띄운 스킬 id 들
var _draw_node: Node2D
var _labels: Array = []           # 카드 텍스트 라벨들


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP   # 뒤로 입력 안 새게
	visible = false
	# 게임이 멈춰도(paused) 이 패널은 계속 작동해야 한다
	process_mode = Node.PROCESS_MODE_ALWAYS
	if main and main.has_method("get_kfont"):
		kfont = main.get_kfont()
	# 그림 그릴 노드(_draw)
	_draw_node = Node2D.new()
	_draw_node.set_script(_make_draw_script())
	_draw_node.set("panel", self)
	add_child(_draw_node)
	gui_input.connect(_on_input)


# 레벨업 1회분을 큐에 더하고, 떠 있지 않으면 처리 시작 (mino1 _gainXP 끝부분)
func queue_levelup(count: int) -> void:
	pending += count
	process_queue()


# 큐 소진: 전직 우선 → 레벨업 카드. 띄울 게 있으면 하나 띄우고 멈춘다 (mino1 _processLevelupQueue)
func process_queue() -> void:
	if active:
		return
	# 전직(Lv10/25) 우선 — 떴으면 전직 후 JobPanel 이 이 함수를 다시 부른다 (mino1 _checkJobUnlocks)
	if main and main.has_method("check_job_unlock") and main.check_job_unlock():
		return
	while pending > 0:
		pending -= 1
		if _open():
			return     # 패널 떴음 → 선택 대기
		# 못 띄움(더 배울 스킬 없음) → 남은 큐 계속 소진
	# 큐가 비면 멈춤 해제
	_unpause()


# 선택지 3개 뽑아 패널을 띄운다. 띄우면 true (mino1 _openLvlupPanel)
func _open() -> bool:
	var p: Dictionary = GameState.player
	var skills: Dictionary = p.get("skills", {})
	var lvl := int(p.get("lvl", 1))

	# 스택·레벨 조건을 만족하는 스킬 풀
	var pool: Array = []
	for id in GameData.SKILL_DEFS.keys():
		var d: Dictionary = GameData.SKILL_DEFS[id]
		var stack := int(skills.get(id, 0))
		if stack < int(d["max_stack"]) and lvl >= int(d["min_lvl"]):
			pool.append(id)
	if pool.is_empty():
		return false

	# 3개 랜덤 (결정론 RNG — mino1 this._rng 사용)
	var rng: GameData.RNG = main.core_rng()
	var tmp := pool.duplicate()
	_options = []
	for i in range(min(3, tmp.size())):
		var k := int(floor(rng.next() * tmp.size()))
		k = clampi(k, 0, tmp.size() - 1)
		_options.append(tmp[k])
		tmp.remove_at(k)
	if _options.is_empty():
		return false

	active = true
	visible = true
	_pause()
	_build()
	return true


func _build() -> void:
	_clear_labels()
	_card_rects = []
	var p: Dictionary = GameState.player
	var skills: Dictionary = p.get("skills", {})

	var w := size.x
	var h := size.y
	var cw := minf(w * 0.82, 560.0)
	var ch := 130.0
	var gap := 18.0
	var sx := (w - cw) / 2.0
	var sy := (h - _options.size() * (ch + gap)) / 2.0

	# 제목
	var title := _mk("레벨 업!  스킬 선택", 30, Color8(0xff, 0xcf, 0x5c))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(w, 40)
	title.position = Vector2(0, sy - 56.0)

	for i in range(_options.size()):
		var id: String = _options[i]
		var d: Dictionary = GameData.SKILL_DEFS[id]
		var st := int(skills.get(id, 0))
		var cy := sy + i * (ch + gap)
		var rect := Rect2(sx, cy, cw, ch)
		_card_rects.append({"rect": rect, "id": id})

		# 이름 (아이콘은 폰트에 없을 수 있어 제외, 이름만)
		var name_lbl := _mk(str(d["name"]), 24, Color8(0xff, 0xcf, 0x5c))
		name_lbl.position = Vector2(sx + 22.0, cy + 18.0)
		# 설명
		var desc_lbl := _mk(str(d["desc"]), 18, Color8(0xcd, 0xd6, 0xc2))
		desc_lbl.position = Vector2(sx + 22.0, cy + 58.0)
		desc_lbl.size = Vector2(cw - 44.0, 30)
		# 보유 스택
		if st > 0:
			var dots := "●".repeat(st) + "○".repeat(int(d["max_stack"]) - st)
			var stack_lbl := _mk("보유 " + dots, 16, Color8(0x8f, 0xb0, 0x8f))
			stack_lbl.position = Vector2(sx + 22.0, cy + 92.0)

	_draw_node.queue_redraw()


func _on_input(event: InputEvent) -> void:
	if not active:
		return
	var pos := Vector2.ZERO
	var pressed := false
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
		pressed = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pos = event.position
		pressed = true
	if not pressed:
		return
	for card in _card_rects:
		if (card["rect"] as Rect2).has_point(pos):
			_apply(card["id"])
			return


# 스킬 적용 (mino1 _applySkill) — 효과는 Main.apply_skill 에 위임(전투와 한 곳)
func _apply(id: String) -> void:
	if main and main.has_method("apply_skill"):
		main.apply_skill(id)
	active = false
	visible = false
	_clear_labels()
	_card_rects = []
	_options = []
	_draw_node.queue_redraw()
	# 남은 레벨업이 있으면 다음 선택창을 이어서
	process_queue()


func _pause() -> void:
	get_tree().paused = true


func _unpause() -> void:
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


# 카드 배경을 그리는 Node2D 스크립트
func _make_draw_script() -> GDScript:
	var src := """
extends Node2D
var panel
func _draw():
	if panel == null or not panel.active:
		return
	var w = panel.size.x
	var h = panel.size.y
	# 어두운 오버레이
	draw_rect(Rect2(0, 0, w, h), Color(0.047, 0.059, 0.039, 0.9), true)
	for card in panel._card_rects:
		var r = card['rect']
		draw_rect(r, Color(0.118, 0.165, 0.094, 1.0), true)
		# 테두리(골드)
		var pts = PackedVector2Array([
			r.position, Vector2(r.position.x + r.size.x, r.position.y),
			Vector2(r.position.x + r.size.x, r.position.y + r.size.y),
			Vector2(r.position.x, r.position.y + r.size.y), r.position])
		draw_polyline(pts, Color(1.0, 0.812, 0.361), 2.5, true)
"""
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s
