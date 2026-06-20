extends Control
class_name HUD
## HUD — 화면 상단 정보판. mino1 의 _drawHUD 대응.
## 레벨 뱃지 + HP/MP/XP 바 + 직업·킬·골드 + 우상단 퀘스트(목표) 텍스트.
## 한 프레임에 한 번 _draw 로 직접 그린다(mino1 Phaser Graphics 와 같은 방식).
## 숫자 라벨(레벨·HP·MP·골드·퀘스트)은 Label 노드로 얹어 Jua 폰트가 적용되게 한다.

var main: Node = null          # Main 참조 (kfont·게임상태 접근)
var kfont: Font = null

# 화면 상단 패널 레이아웃 (mino1 과 같은 값 — 세로 720 폭 기준으로 살짝 키움)
var _bdg_r := 32.0            # 레벨 뱃지 반지름
var _bdg_x := 0.0
var _bdg_y := 0.0
var _hp_panel_x := 0.0
var _hp_panel_y := 14.0
var _hp_panel_w := 220.0     # 720 폭이라 mino1(130) 보다 넓게
var _hp_panel_h := 86.0

# 라벨(폰트 텍스트) — 그림 위에 얹는다
var _lv_mini: Label           # "Lv"
var _lv_num: Label            # 레벨 숫자
var _job_kill: Label          # 직업·킬
var _gold_lbl: Label          # 골드
var _hp_lbl: Label
var _mp_lbl: Label
var _quest_lbl: Label         # 우상단 목표


func _ready() -> void:
	# 화면 전체를 덮되 입력은 통과시킨다 (조이스틱·버튼이 아래에서 받게)
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if main and main.has_method("get_kfont"):
		kfont = main.get_kfont()

	# 레이아웃 좌표 계산
	_bdg_x = _bdg_r + 12.0
	_bdg_y = _bdg_r + 18.0
	_hp_panel_x = _bdg_x + _bdg_r + 12.0

	_make_labels()


func _make_labels() -> void:
	_lv_mini = _mk("Lv", 16, Color8(0xff, 0xcf, 0x5c))
	_lv_num = _mk("1", 34, Color8(0xff, 0xcf, 0x5c))
	_lv_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lv_mini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_job_kill = _mk("킬 0", 18, Color8(0xcd, 0xd6, 0xc2))
	_gold_lbl = _mk("G 0", 18, Color8(0xff, 0xd2, 0x4a))
	_hp_lbl = _mk("100/100", 18, Color.WHITE)
	_hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mp_lbl = _mk("100/100", 15, Color8(0xcc, 0xee, 0xff))
	_mp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quest_lbl = _mk("", 20, Color8(0xe8, 0xf0, 0xd8))
	_quest_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _mk(txt: String, size: int, col: Color) -> Label:
	var l := Label.new()
	if kfont:
		l.add_theme_font_override("font", kfont)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	l.text = txt
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _process(_delta: float) -> void:
	queue_redraw()
	_update_labels()


# mino1 _drawHUD — 패널·뱃지·HP/MP/XP 바를 직접 그린다
func _draw() -> void:
	var p: Dictionary = GameState.player
	var panel_w := _bdg_x + _bdg_r + _hp_panel_w + 24.0

	# 배경 패널 (둥근 직사각, 반투명 어둠)
	_round_rect(Rect2(6, 6, panel_w, _hp_panel_h + 12.0), 14.0, Color8(0x0a, 0x0f, 0x07, 0xb8))
	_round_rect_outline(Rect2(6, 6, panel_w, _hp_panel_h + 12.0), 14.0, Color(0.29, 0.42, 0.23, 0.9), 1.5)

	# 레벨 뱃지 (원형 + 발광)
	draw_circle(Vector2(_bdg_x, _bdg_y), _bdg_r + 4.0, Color8(0xff, 0xcf, 0x5c, 0x33))
	draw_circle(Vector2(_bdg_x, _bdg_y), _bdg_r, Color8(0x2a, 0x1a, 0x08))
	draw_arc(Vector2(_bdg_x, _bdg_y), _bdg_r, 0.0, TAU, 40, Color8(0xff, 0xcf, 0x5c), 2.5)
	draw_circle(Vector2(_bdg_x - 5.0, _bdg_y - 6.0), _bdg_r * 0.55, Color8(0xff, 0xcf, 0x5c, 0x20))

	# HP 바
	var hp_pct := clampf(float(p.get("hp", 0)) / maxf(1.0, float(p.get("maxhp", 1))), 0.0, 1.0)
	var hp_bar_y := _hp_panel_y + 8.0
	var hp_bar_h := 20.0
	var bar_x := _hp_panel_x + 28.0
	var bar_w := _hp_panel_w - 28.0
	# "HP" 라벨 칩 (빨강)
	_round_rect(Rect2(_hp_panel_x, hp_bar_y - 2.0, 24.0, hp_bar_h + 4.0), 4.0, Color8(0xff, 0x5c, 0x5c, 0xe6))
	# 바 배경
	_round_rect(Rect2(bar_x, hp_bar_y, bar_w, hp_bar_h), 6.0, Color8(0x1a, 0x08, 0x08))
	# 바 전경 (체력에 따라 색)
	var hp_col := Color8(0x4c, 0xdd, 0x88)
	if hp_pct <= 0.28:
		hp_col = Color8(0xff, 0x3c, 0x3c)
	elif hp_pct <= 0.55:
		hp_col = Color8(0xff, 0xcf, 0x3c)
	if hp_pct > 0.0:
		_round_rect(Rect2(bar_x, hp_bar_y, bar_w * hp_pct, hp_bar_h), 6.0, hp_col)
		if hp_pct > 0.05:
			_round_rect(Rect2(bar_x + 2.0, hp_bar_y + 2.0, (bar_w - 4.0) * hp_pct, 5.0), 3.0, Color(1, 1, 1, 0.18))
	_round_rect_outline(Rect2(bar_x, hp_bar_y, bar_w, hp_bar_h), 6.0, Color(0.48, 0.6, 0.48, 0.8), 1.5)

	# MP 바
	var mp_pct := 0.0
	if float(p.get("maxmp", 0)) > 0.0:
		mp_pct = clampf(float(p.get("mp", 0)) / float(p.get("maxmp", 1)), 0.0, 1.0)
	var mp_bar_y := hp_bar_y + hp_bar_h + 5.0
	var mp_bar_h := 15.0
	_round_rect(Rect2(_hp_panel_x, mp_bar_y - 1.0, 24.0, mp_bar_h + 2.0), 3.0, Color8(0x22, 0x44, 0xcc, 0xe6))
	_round_rect(Rect2(bar_x, mp_bar_y, bar_w, mp_bar_h), 5.0, Color8(0x08, 0x08, 0x20))
	if mp_pct > 0.0:
		_round_rect(Rect2(bar_x, mp_bar_y, bar_w * mp_pct, mp_bar_h), 5.0, Color8(0x44, 0xaa, 0xff))
		_round_rect(Rect2(bar_x + 2.0, mp_bar_y + 1.0, (bar_w - 4.0) * mp_pct, 4.0), 2.0, Color(0.53, 0.87, 1.0, 0.35))
	_round_rect_outline(Rect2(bar_x, mp_bar_y, bar_w, mp_bar_h), 5.0, Color(0.13, 0.33, 0.67, 0.8), 1.0)

	# XP 바 (가늘게)
	var xp_pct := 0.0
	if int(p.get("xpNext", 0)) > 0:
		xp_pct = clampf(float(p.get("xp", 0)) / float(p.get("xpNext", 1)), 0.0, 1.0)
	var xp_bar_y := mp_bar_y + mp_bar_h + 5.0
	var xp_bar_h := 8.0
	_round_rect(Rect2(_hp_panel_x, xp_bar_y, bar_w + 28.0, xp_bar_h), 3.0, Color8(0x0d, 0x1a, 0x2a))
	if xp_pct > 0.0:
		_round_rect(Rect2(_hp_panel_x, xp_bar_y, (bar_w + 28.0) * xp_pct, xp_bar_h), 3.0, Color8(0x44, 0xaa, 0xff))
		_round_rect(Rect2(_hp_panel_x + 1.0, xp_bar_y + 1.0, (bar_w + 28.0) * xp_pct - 2.0, 3.0), 2.0, Color(0.53, 0.87, 1.0, 0.45))
	_round_rect_outline(Rect2(_hp_panel_x, xp_bar_y, bar_w + 28.0, xp_bar_h), 3.0, Color(0.13, 0.33, 0.67, 0.8), 1.0)


func _update_labels() -> void:
	var p: Dictionary = GameState.player
	# 레벨 뱃지 텍스트
	_lv_mini.size = Vector2(40, 18)
	_lv_mini.position = Vector2(_bdg_x - 20.0, _bdg_y - _bdg_r * 0.72)
	_lv_num.size = Vector2(60, 40)
	_lv_num.position = Vector2(_bdg_x - 30.0, _bdg_y - _bdg_r * 0.16)
	_lv_num.text = str(int(p.get("lvl", 1)))

	# 직업·킬 (뱃지 아래)
	var job_name := _job_display_name()
	var kills := int(p.get("kills", 0))
	_job_kill.position = Vector2(_bdg_x - _bdg_r + 2.0, _bdg_y + _bdg_r + 8.0)
	_job_kill.text = ("%s · 킬 %d" % [job_name, kills]) if job_name != "" else ("킬 %d" % kills)

	# 골드 (직업·킬 아래)
	_gold_lbl.position = Vector2(_bdg_x - _bdg_r + 2.0, _bdg_y + _bdg_r + 30.0)
	_gold_lbl.text = "G %d" % int(p.get("gold", 0))

	# HP 수치 (바 가운데)
	var bar_x := _hp_panel_x + 28.0
	var bar_w := _hp_panel_w - 28.0
	var hp_bar_y := _hp_panel_y + 8.0
	_hp_lbl.size = Vector2(bar_w, 22)
	_hp_lbl.position = Vector2(bar_x, hp_bar_y - 1.0)
	_hp_lbl.text = "%d/%d" % [int(p.get("hp", 0)), int(p.get("maxhp", 0))]

	var mp_bar_y := hp_bar_y + 20.0 + 5.0
	_mp_lbl.size = Vector2(bar_w, 17)
	_mp_lbl.position = Vector2(bar_x, mp_bar_y - 1.0)
	_mp_lbl.text = "%d/%d" % [int(p.get("mp", 0)), int(p.get("maxmp", 0))]

	# 우상단 퀘스트(목표) 텍스트
	_quest_lbl.text = _quest_text()
	_quest_lbl.size = Vector2(size.x - 24.0, 28)
	_quest_lbl.position = Vector2(12.0, 14.0)


# 직업 표시 이름 (전직은 S3 — 지금은 빈 문자열)
func _job_display_name() -> String:
	var p: Dictionary = GameState.player
	var job = p.get("job", null)
	if job == null:
		return ""
	var names := {"warrior": "전사", "mage": "마법사", "rogue": "도적",
		"magic_swordsman": "마검사", "archmage": "대마법사", "ninja": "닌자"}
	var job2 = p.get("job2", null)
	if job2 != null and names.has(job2):
		return names[job2]
	return names.get(job, "")


# 목표 텍스트 (mino1 questStr — 지역명·킬 목표·보스). 보스/지역은 S5에서 채운다.
func _quest_text() -> String:
	var p: Dictionary = GameState.player
	var region_idx: int = clampi(GameState.region, 0, GameData.REGION_DEFS.size() - 1)
	var rdef: Dictionary = GameData.REGION_DEFS[region_idx]
	var rname: String = rdef.get("name", "제%d장" % (region_idx + 1))
	var boss_names := {"boar_king": "우두머리 멧돼지", "croc": "심연의 악어",
		"wolf_king": "우두머리 늑대", "elephant": "오염의 군주"}
	var boss_name: String = boss_names.get(rdef.get("boss", ""), "보스")
	var chapter := region_idx + 1
	var boss_kill_target := 12 + chapter * 4
	var kills := int(p.get("kills", 0))
	return "%s — 변이체 %d/%d · %s를 깨워라" % [rname, kills, boss_kill_target, boss_name]


# ── 둥근 사각형 채우기 헬퍼 (Godot 엔 fillRoundedRect 가 없어 직접) ──
func _round_rect(r: Rect2, radius: float, col: Color) -> void:
	radius = minf(radius, minf(r.size.x, r.size.y) / 2.0)
	if radius <= 0.5:
		draw_rect(r, col, true)
		return
	# 가운데 십자 + 네 모서리 원으로 둥근 사각 근사
	draw_rect(Rect2(r.position.x + radius, r.position.y, r.size.x - radius * 2.0, r.size.y), col, true)
	draw_rect(Rect2(r.position.x, r.position.y + radius, r.size.x, r.size.y - radius * 2.0), col, true)
	var tl := r.position + Vector2(radius, radius)
	var tr := Vector2(r.position.x + r.size.x - radius, r.position.y + radius)
	var bl := Vector2(r.position.x + radius, r.position.y + r.size.y - radius)
	var br := Vector2(r.position.x + r.size.x - radius, r.position.y + r.size.y - radius)
	draw_circle(tl, radius, col)
	draw_circle(tr, radius, col)
	draw_circle(bl, radius, col)
	draw_circle(br, radius, col)


func _round_rect_outline(r: Rect2, radius: float, col: Color, w: float) -> void:
	radius = minf(radius, minf(r.size.x, r.size.y) / 2.0)
	var pts := PackedVector2Array()
	var steps := 5
	# 네 모서리 호를 이어 폴리라인으로
	var corners := [
		[Vector2(r.position.x + r.size.x - radius, r.position.y + radius), -PI / 2.0, 0.0],
		[Vector2(r.position.x + r.size.x - radius, r.position.y + r.size.y - radius), 0.0, PI / 2.0],
		[Vector2(r.position.x + radius, r.position.y + r.size.y - radius), PI / 2.0, PI],
		[Vector2(r.position.x + radius, r.position.y + radius), PI, PI * 1.5],
	]
	for c in corners:
		var center: Vector2 = c[0]
		var a0: float = c[1]
		var a1: float = c[2]
		for i in range(steps + 1):
			var a := a0 + (a1 - a0) * (float(i) / float(steps))
			pts.append(center + Vector2(cos(a), sin(a)) * radius)
	pts.append(pts[0])
	draw_polyline(pts, col, w, true)
