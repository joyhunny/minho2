extends Control
class_name SkillTray
## SkillTray — 화면 우하단 스킬 버튼 묶음. mino1 _drawSkillBtns/_getSkillBtnPositions 대응.
## 공격 버튼 위로 2줄 6개(파이어볼·메테오·순간이동 / 무적·워터폴·소환) + 좌측에 전직 스킬 버튼.
## 쿨다운 파이·마나 부족 회색·아이콘·쿨타임 숫자를 매 프레임 그린다.
## 버튼을 탭하면 SkillSystem.cast_skill(key) / 전직 버튼은 SkillMenu 를 연다.

var main: Node = null
var kfont: Font = null

# 6개 기본 스킬 순서·아이콘 (mino1 skillKeys/skillIcons)
const SKILL_KEYS := ["fireball", "meteor", "teleport", "invincible", "waterfall", "summon_ally"]
const SKILL_ICONS := ["🔥", "☄", "⚡", "✨", "💧", "🐛"]
const SKILL_NAMES := ["파이어볼", "메테오", "순간이동", "무적", "워터폴", "소환"]

var _btns: Array = []           # [{pos, r}] — 6개 기본 스킬 버튼
var _ult_btn := {}              # {pos, r} — 전직 스킬 버튼 (있을 때만)
var _draw_node: Node2D
var _icon_labels: Array = []    # 6 아이콘 라벨
var _cd_labels: Array = []      # 6 쿨타임 라벨
var _ult_icon: Label
var skills: Node = null         # SkillSystem


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	# 그리기 전용 — 입력은 Main 이 try_hit() 으로 먼저 검사한다(조이스틱/공격과 충돌 방지).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if main and main.has_method("get_kfont"):
		kfont = main.get_kfont()
	if main:
		skills = main.skills
	_draw_node = Node2D.new()
	_draw_node.set_script(_make_draw_script())
	_draw_node.set("tray", self)
	add_child(_draw_node)
	for i in 6:
		_icon_labels.append(_mk(SKILL_ICONS[i], 22, Color.WHITE))
		var cd := _mk("", 12, Color.WHITE)
		cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_cd_labels.append(cd)
	_ult_icon = _mk("", 26, Color.WHITE)
	_ult_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _process(_delta: float) -> void:
	_layout()
	_update_labels()
	_draw_node.queue_redraw()


# 버튼 위치 계산 (mino1 _getSkillBtnPositions) — 공격 버튼 기준 2줄
func _layout() -> void:
	var w := size.x
	var h := size.y
	var is_small := w <= 460.0
	var btn_r := 28.0 if is_small else 26.0
	var gap := 10.0 if is_small else 8.0
	var step := btn_r * 2.0 + gap
	# 공격 버튼 영역 (Main 의 AtkButton: offset_left=-180..right=-40, top=-200..bottom=-60)
	# 공격 버튼 중심 X에 오른쪽 끝을 맞추고, 줄은 공격 버튼 '위쪽 바깥'에 둔다
	# (공격 버튼 사각형과 안 겹치게 — 겹치면 탭이 공격 Control 에 먹힘).
	var atk_x := w - 110.0
	var atk_top := h - 200.0
	var row1_y := atk_top - btn_r - 6.0
	var row2_y := row1_y - (btn_r * 2.0 + gap) - 4.0
	_btns = []
	for i in 3:
		_btns.append({"pos": Vector2(atk_x - (2 - i) * step, row1_y), "r": btn_r})
	for i in 3:
		_btns.append({"pos": Vector2(atk_x - (2 - i) * step, row2_y), "r": btn_r})
	# 전직 스킬 버튼: 위 줄 왼쪽 옆 (직업 스킬 있을 때만)
	if skills and skills.my_class_skills().size() > 0:
		_ult_btn = {"pos": Vector2(atk_x - 3 * step, row2_y), "r": btn_r + 2.0}
	else:
		_ult_btn = {}


func _update_labels() -> void:
	var p: Dictionary = GameState.player
	for i in 6:
		if i >= _btns.size():
			continue
		var b: Dictionary = _btns[i]
		var pos: Vector2 = b["pos"]
		var key: String = SKILL_KEYS[i]
		var can: bool = skills.can_cast(key) if skills else false
		_icon_labels[i].position = Vector2(pos.x - 14.0, pos.y - 16.0)
		_icon_labels[i].modulate.a = 1.0 if can else 0.30
		var cd := float(skills.skills[key]["cd"]) if skills else 0.0
		if cd > 0.0:
			_cd_labels[i].text = "%.1f" % cd
			_cd_labels[i].size = Vector2(40, 16)
			_cd_labels[i].position = Vector2(pos.x - 20.0, pos.y + b["r"] - 14.0)
			_cd_labels[i].visible = true
		else:
			_cd_labels[i].visible = false
	# 전직 스킬 버튼 아이콘
	if not _ult_btn.is_empty():
		var cls = p.get("job2", null)
		if cls == null:
			cls = p.get("job", null)
		var icon := "⚔️"
		match cls:
			"archmage": icon = "🔮"
			"mage": icon = "✨"
			"ninja": icon = "🥷"
			"rogue": icon = "🗡️"
			"swordmaster", "warrior": icon = "⚔️"
		var up: Vector2 = _ult_btn["pos"]
		_ult_icon.text = icon
		_ult_icon.size = Vector2(40, 32)
		_ult_icon.position = Vector2(up.x - 20.0, up.y - 16.0)
		_ult_icon.visible = true
	else:
		_ult_icon.visible = false


# Main 이 누름 위치를 넘겨 버튼 적중을 검사한다. 적중하면 발동하고 true (입력 소비).
# (조이스틱·공격 버튼보다 먼저 호출되어, 버튼 위 탭이 이동으로 새는 걸 막는다.)
func try_hit(pos: Vector2) -> bool:
	_layout()
	# 전직 스킬 버튼 먼저
	if not _ult_btn.is_empty():
		if pos.distance_to(_ult_btn["pos"]) <= float(_ult_btn["r"]) + 12.0:
			if main and main.skill_menu:
				main.skill_menu.open()
			return true
	# 6개 기본 스킬 버튼
	for i in range(_btns.size()):
		var b: Dictionary = _btns[i]
		if pos.distance_to(b["pos"]) <= float(b["r"]) + 12.0:
			if skills:
				skills.cast_skill(SKILL_KEYS[i])
			return true
	return false


func _mk(txt: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	if kfont:
		l.add_theme_font_override("font", kfont)
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 3)
	l.text = txt
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _make_draw_script() -> GDScript:
	var src := """
extends Node2D
var tray
func _draw():
	if tray == null or tray.skills == null:
		return
	for i in range(tray._btns.size()):
		var b = tray._btns[i]
		var pos = b['pos']
		var r = b['r']
		var key = tray.SKILL_KEYS[i]
		var can = tray.skills.can_cast(key)
		var cd = float(tray.skills.skills[key]['cd'])
		var max_cd = float(tray.skills.skills[key]['max_cd'])
		var theme = _theme_col(key)
		# 외곽 발광
		draw_arc(pos, r + 4, 0.0, TAU, 32, Color(theme.r, theme.g, theme.b, 0.55 if can else 0.15), 2.5)
		# 본체
		draw_circle(pos, r, Color(0.04, 0.04, 0.125, 0.88) if can else Color(0.05, 0.05, 0.05, 0.88))
		draw_arc(pos, r, 0.0, TAU, 32, Color(theme.r, theme.g, theme.b, 0.9 if can else 0.35), 1.8)
		# 쿨타임 파이 (어두운 부채꼴 + 흰 호)
		if cd > 0.0 and max_cd > 0.0:
			var cd_pct = cd / max_cd
			draw_circle(pos, r - 1, Color(0, 0, 0, 0.6 * cd_pct))
			var start_a = -PI / 2.0
			var end_a = start_a + (1.0 - cd_pct) * TAU
			draw_arc(pos, r - 3, start_a, end_a, 28, Color(1, 1, 1, 0.65), 2.5)
	# 전직 스킬 버튼
	if not tray._ult_btn.is_empty():
		var p = GameState.player
		var cls = p.get('job2', null)
		if cls == null:
			cls = p.get('job', null)
		var col = _class_col(cls)
		var up = tray._ult_btn['pos']
		var ur = tray._ult_btn['r']
		draw_arc(up, ur + 3, 0.0, TAU, 32, Color(col.r, col.g, col.b, 0.4), 2.0)
		draw_circle(up, ur, Color(0.047, 0.047, 0.094, 0.92))
		draw_arc(up, ur, 0.0, TAU, 32, col, 2.5)

func _theme_col(key):
	if key == 'invincible': return Color(1.0, 0.667, 0.133)
	if key == 'waterfall': return Color(0.267, 0.667, 1.0)
	if key == 'summon_ally': return Color(0.333, 0.8, 0.533)
	return Color(0.533, 0.533, 1.0)

func _class_col(cls):
	if cls == 'archmage' or cls == 'mage': return Color(0.4, 0.8, 1.0)
	if cls == 'ninja' or cls == 'rogue': return Color(0.267, 0.867, 0.667)
	return Color(1.0, 0.4, 0.8)
"""
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s
