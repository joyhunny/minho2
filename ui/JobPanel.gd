extends Control
class_name JobPanel
## JobPanel — 전직 선택창. mino1 _openJobPanel/_applyJob/_openJob2Panel/_applyJob2 대응.
## 1차 전직(전사·마법사·도적, Lv10) = 3택. 2차 전직(마검사·대마법사·닌자, Lv25) = 1택.
## 레벨업 큐 흐름에서 *레벨업 카드보다 먼저* 뜬다(mino1 _checkJobUnlocks 우선순위).
## 떠 있는 동안 게임은 일시정지(get_tree().paused). 직업 스탯·기본 무기 지급은 mino1 값 보존.

var main: Node = null
var kfont: Font = null

var active := false
var mode := 1                     # 1=1차(3택) / 2=2차(1택)
var _card_rects: Array = []       # [{rect, def}]
var _draw_node: Node2D
var _labels: Array = []

# ── 1차 전직 정의 (mino1 _openJobPanel 의 JOBS) — 스탯 보존 ──
const JOBS_1 := [
	{
		"id": "warrior", "name": "검사", "color": Color8(0xff, 0x99, 0x66),
		"desc": "대검 지급 · 최대체력 +90 · 방어 +9 · 근접 공격력 +14\n전선을 지키는 검의 달인. (Lv25 → 마검사)",
		"weapon": "great_sword",
	},
	{
		"id": "mage", "name": "마법사", "color": Color8(0x88, 0xaa, 0xff),
		"desc": "스태프 지급 · 최대마나 +90 · 마나회복 빠름 · 스킬 데미지 +80%\n강력한 스킬이 주력. (Lv25 → 대마법사)",
		"weapon": "mage_staff",
	},
	{
		"id": "rogue", "name": "도적", "color": Color8(0x66, 0xff, 0xaa),
		"desc": "단검 지급 · 이동속도 +55 · 공격속도 40% 가속 · 치명타 +30%\n빠른 발과 일격으로 허를 찌른다. (Lv25 → 닌자)",
		"weapon": "combat_dagger",
	},
]

# ── 2차 전직 정의 (mino1 _advJobFor) — 1차 → 상위직 매핑 ──
const ADV_FOR := {
	"warrior": {
		"id": "swordmaster", "name": "마검사", "color": Color8(0xff, 0x99, 0xdd),
		"desc": "쌍검 지급 · 최대체력 +120 · 공격력 +24 · 방어 +6\n검에 마력을 실어 베는 최강의 전사.",
		"weapon": "twin_blades",
	},
	"mage": {
		"id": "archmage", "name": "대마법사", "color": Color8(0x99, 0xdd, 0xff),
		"desc": "마법 지팡이 지급 · 최대마나 +150 · 스킬 데미지 대폭↑ · 쿨타임 30% 감소\n모든 마법이 강해지는 마법의 정점.",
		"weapon": "harry_wand",
	},
	"rogue": {
		"id": "ninja", "name": "닌자", "color": Color8(0x88, 0xff, 0xcc),
		"desc": "표창 지급 · 이동속도 +40 · 공격속도 대폭↑ · 치명타 +15%\n그림자처럼 빠른 암살자.",
		"weapon": "ninja_shuriken",
	},
}


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


# ── 전직 조건 확인 → 떠야 하면 띄우고 true (mino1 _checkJobUnlocks) ──
# LevelupPanel.process_queue() 가 레벨업 카드보다 먼저 호출한다.
func check_unlock() -> bool:
	if active:
		return true
	var p: Dictionary = GameState.player
	var lvl := int(p.get("lvl", 1))
	# 1차: Lv10 이상, 직업 없음
	if lvl >= 10 and p.get("job", null) == null:
		_open(1)
		return true
	# 2차: Lv25 이상, 1차는 했고 2차는 아직
	if lvl >= 25 and p.get("job", null) != null and p.get("job2", null) == null:
		_open(2)
		return true
	return false


func _open(which: int) -> void:
	mode = which
	active = true
	visible = true
	get_tree().paused = true
	_build()


func _build() -> void:
	_clear_labels()
	_card_rects = []
	var w := size.x
	var h := size.y

	if mode == 1:
		# 제목
		var title := _mk("★ 레벨 10 달성! 전직을 선택하세요", 26, Color8(0xff, 0xdd, 0x44))
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.size = Vector2(w, 36)
		title.position = Vector2(0, h * 0.10)
		var sub := _mk("전직은 한 번만 가능합니다", 16, Color8(0xaa, 0xaa, 0xaa))
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.size = Vector2(w, 24)
		sub.position = Vector2(0, h * 0.10 + 36.0)

		var cw := minf(w * 0.82, 540.0)
		var ch := 140.0
		var gap := 16.0
		var total_h := JOBS_1.size() * (ch + gap) - gap
		var sx := (w - cw) / 2.0
		var sy := (h - total_h) / 2.0 + 20.0
		for i in range(JOBS_1.size()):
			var job: Dictionary = JOBS_1[i]
			var cy := sy + i * (ch + gap)
			_card_rects.append({"rect": Rect2(sx, cy, cw, ch), "def": job})
			var name_lbl := _mk(str(job["name"]), 24, job["color"])
			name_lbl.position = Vector2(sx + 24.0, cy + 16.0)
			var desc_lbl := _mk(str(job["desc"]), 16, Color8(0xcc, 0xcc, 0xcc))
			desc_lbl.position = Vector2(sx + 24.0, cy + 54.0)
			desc_lbl.size = Vector2(cw - 48.0, ch - 60.0)
			desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		var p: Dictionary = GameState.player
		var job1 = p.get("job", null)
		var adv = ADV_FOR.get(job1, null)
		if adv == null:
			# 안전장치: 매핑 없으면 그냥 닫고 진행
			p["job2"] = "none"
			_close_and_continue()
			return
		var title2 := _mk("★ 레벨 25 달성! 2차 전직!", 26, Color8(0xff, 0xdd, 0x44))
		title2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title2.size = Vector2(w, 36)
		title2.position = Vector2(0, h * 0.18)

		var cw2 := minf(w * 0.84, 520.0)
		var ch2 := 180.0
		var sx2 := (w - cw2) / 2.0
		var cy2 := (h - ch2) / 2.0 + 10.0
		_card_rects.append({"rect": Rect2(sx2 - 20.0, cy2, cw2 + 40.0, ch2 + 44.0), "def": adv})
		var name2 := _mk(str(adv["name"]), 28, adv["color"])
		name2.position = Vector2(sx2 + 26.0, cy2 + 20.0)
		var desc2 := _mk(str(adv["desc"]), 17, Color8(0xcc, 0xcc, 0xcc))
		desc2.position = Vector2(sx2 + 26.0, cy2 + 66.0)
		desc2.size = Vector2(cw2 - 52.0, ch2 - 70.0)
		desc2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var tap := _mk("👆 탭하여 전직!", 18, Color8(0xff, 0xdd, 0x44))
		tap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tap.size = Vector2(w, 28)
		tap.position = Vector2(0, cy2 + ch2 + 14.0)

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
			_apply(card["def"])
			return


# ── 전직 적용 (mino1 _applyJob/_applyJob2) — 스탯·무기 지급 보존 ──
func _apply(def: Dictionary) -> void:
	var p: Dictionary = GameState.player
	var id: String = def["id"]
	if mode == 1:
		p["job"] = id
		_apply_job1_stats(id, p)
	else:
		p["job2"] = id
		_apply_job2_stats(id, p)

	# 기본 무기 지급 + 자동 장착 (S4: InventorySystem 이 장착/해제 단일 권한 — 그쪽에 위임)
	var weapon = def.get("weapon", null)
	if weapon != null and GameData.ITEM_DEFS.has(weapon):
		if main and main.inventory:
			main.inventory.equip("weapon", weapon)
			main.show_pickup_toast("무기 지급: " + str(GameData.ITEM_DEFS[weapon].get("name", weapon)))
		else:
			_equip_weapon(weapon, p)   # 안전 폴백 (인벤토리 미빌드 시)

	# 전직 완료 연출 (파티클 + 흔들림 + 메시지)
	if main:
		main.fx.add_particles(main.player.global_position, Color8(0xff, 0xdd, 0x44), 30)
		main.spawn_impact(main.player.global_position, 90.0, Color8(0xff, 0xdd, 0x44))
		main.add_shake(0.25, 8.0)
		main.show_center_message("%s 전직 완료!" % def["name"])
	GameState.save_game()
	_close_and_continue()


# 1차 전직 스탯 (mino1 JOBS[].apply)
func _apply_job1_stats(id: String, p: Dictionary) -> void:
	match id:
		"warrior":
			p["maxhp"] = float(p["maxhp"]) + 90.0
			p["hp"] = minf(float(p["maxhp"]), float(p["hp"]) + 90.0)
			p["armor"] = float(p.get("armor", 0)) + 9.0
			p["atkPow"] = float(p["atkPow"]) + 14.0
		"mage":
			p["maxmp"] = float(p["maxmp"]) + 90.0
			p["mp"] = minf(float(p["maxmp"]), float(p["mp"]) + 90.0)
			p["atkPow"] = maxf(4.0, float(p["atkPow"]) - 4.0)
		"rogue":
			p["sp"] = minf(360.0, float(p["sp"]) + 55.0)
			p["atkSpeed"] = maxf(0.10, float(p["atkSpeed"]) * 0.6)
			p["maxhp"] = maxf(40.0, float(p["maxhp"]) - 25.0)
			p["hp"] = minf(float(p["maxhp"]), float(p["hp"]))


# 2차 전직 스탯 (mino1 ADV[].apply)
func _apply_job2_stats(id: String, p: Dictionary) -> void:
	match id:
		"swordmaster":
			p["maxhp"] = float(p["maxhp"]) + 120.0
			p["hp"] = minf(float(p["maxhp"]), float(p["hp"]) + 120.0)
			p["atkPow"] = float(p["atkPow"]) + 24.0
			p["armor"] = float(p.get("armor", 0)) + 6.0
		"archmage":
			p["maxmp"] = float(p["maxmp"]) + 150.0
			p["mp"] = float(p["maxmp"])
		"ninja":
			p["sp"] = minf(400.0, float(p["sp"]) + 40.0)
			p["atkSpeed"] = maxf(0.08, float(p["atkSpeed"]) * 0.7)
			p["maxhp"] = float(p["maxhp"]) + 40.0
			p["hp"] = minf(float(p["maxhp"]), float(p["hp"]) + 40.0)


# 무기 장착 — S4 인벤토리 전이라 무기 스탯만 직접 합산하고 equip 슬롯에 기록.
# (이전 무기가 있으면 그 스탯을 먼저 빼고 새 무기 스탯을 더한다 — 중복 합산 방지.)
func _equip_weapon(item_id: String, p: Dictionary) -> void:
	var equip: Dictionary = p.get("equip", {})
	var prev = equip.get("weapon", null)
	if prev != null and GameData.ITEM_DEFS.has(prev):
		_apply_item_stats(GameData.ITEM_DEFS[prev].get("stats", {}), p, -1.0)
	equip["weapon"] = item_id
	p["equip"] = equip
	_apply_item_stats(GameData.ITEM_DEFS[item_id].get("stats", {}), p, 1.0)
	if main:
		main.show_pickup_toast("무기 지급: " + str(GameData.ITEM_DEFS[item_id].get("name", item_id)))


func _apply_item_stats(stats: Dictionary, p: Dictionary, sign_v: float) -> void:
	for key in stats.keys():
		var delta := float(stats[key]) * sign_v
		match key:
			"atkPow":
				p["atkPow"] = float(p.get("atkPow", 0)) + delta
			"atkRange":
				p["atkRange"] = float(p.get("atkRange", 64)) + delta
			"atkSpeed":
				p["atkSpeed"] = maxf(0.08, float(p.get("atkSpeed", 0.5)) + delta)
			"armor":
				p["armor"] = float(p.get("armor", 0)) + delta
			"maxhp":
				p["maxhp"] = float(p.get("maxhp", 0)) + delta
				p["hp"] = minf(float(p["maxhp"]), float(p.get("hp", 0)) + maxf(0.0, delta))
			"maxmp":
				p["maxmp"] = float(p.get("maxmp", 0)) + delta
				p["mp"] = minf(float(p["maxmp"]), float(p.get("mp", 0)) + maxf(0.0, delta))


func _close_and_continue() -> void:
	active = false
	visible = false
	_clear_labels()
	_card_rects = []
	_draw_node.queue_redraw()
	# 전직 후 남은 레벨업 큐를 이어서 (mino1 _closeJobPanel → _processLevelupQueue)
	if main and main.lvlup_panel:
		main.lvlup_panel.process_queue()
	else:
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
	draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.90), true)
	for card in panel._card_rects:
		var r = card['rect']
		var col = card['def']['color']
		draw_rect(r, Color(0.047, 0.047, 0.094, 1.0), true)
		var pts = PackedVector2Array([
			r.position, Vector2(r.position.x + r.size.x, r.position.y),
			Vector2(r.position.x + r.size.x, r.position.y + r.size.y),
			Vector2(r.position.x, r.position.y + r.size.y), r.position])
		draw_polyline(pts, col, 2.5, true)
		# 왼쪽 색상 바
		draw_rect(Rect2(r.position.x, r.position.y, 8, r.size.y), Color(col.r, col.g, col.b, 0.6), true)
"""
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s
