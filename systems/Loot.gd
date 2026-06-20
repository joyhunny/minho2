extends Node2D
class_name LootSystem
## LootSystem — 바닥 장비 드랍·줍기 + 날고기 드랍·그릴·요리(굽기)를 월드 좌표에 그린다.
## mino1 play.js 의 _addGroundItem/_updateGroundItems + _spawnRawMeat/_drawGrill/_updateCookingSystem 대응.
## 드랍 자체(tryDrop·날고기 확률)는 Main.on_enemy_died 가 호출해 여기로 넣는다.
## 밸런스 숫자(20초 소멸·자동줍기 거리·45초 상함·굽기 3초·확률)는 mino1 값 그대로 보존.

const GROUND_LIFE := 20.0      # 바닥 장비 20초 후 소멸 (mino1)
const GROUND_PICKUP := 40.0    # 자동 줍기 거리 (mino1)
const MEAT_SPOIL := 45.0       # 날고기/구운고기 45초 후 상함 (mino1 _MEAT_SPOIL)
const MEAT_PICKUP := 44.0      # 고기 자동 줍기 거리 (mino1)
const MAX_MEAT_ITEMS := 12     # 바닥 날고기 최대 (mino1 MAX_MEAT)
const COOK_TIME := 3.0         # 굽는 시간(초) (mino1 grill.COOK_TIME)
const GRILL_NEAR := 68.0       # 그릴 작동 거리 (mino1 nearGrill)

var main: Node = null
var kfont: Font = null

# 바닥 장비 아이템: [{x, y, item_id, t}]
var ground_items: Array = []
var _ground_labels: Array = []   # 각 ground_item 의 이름 라벨 (병행 배열)

# 바닥 날고기: [{x, y, t, spoil_t}]
var meat_items: Array = []

# 보유 고기 (mino1 _rawMeat/_cookedMeat — 저장 안 함, 세션 한정)
var raw_meat := 0
var cooked_meat := 0
var _meat_spoil_timer := 0.0     # 보유 고기 상함 누적 타이머

# 그릴(맵 고정 3개): [{x, y, cooking, cook_t, smoke_t}]
var grills: Array = []

# 굽기 진행 메시지(가장 가까운 그릴) — CookHUD 가 읽어 표시
var cook_msg := ""


func _ready() -> void:
	if main and main.has_method("get_kfont"):
		kfont = main.get_kfont()
	_init_grills()


# 그릴 3개를 맵 중앙 주변에 고정 배치 (mino1 grillDefs)
func _init_grills() -> void:
	var cx0 := GameData.WORLD_W / 2.0
	var cy0 := GameData.WORLD_H / 2.0
	var defs := [
		Vector2(cx0 + 220.0, cy0 + 120.0),
		Vector2(cx0 - 250.0, cy0 - 160.0),
		Vector2(cx0 + 80.0,  cy0 - 280.0),
	]
	for pos in defs:
		grills.append({"x": pos.x, "y": pos.y, "cooking": false, "cook_t": 0.0, "smoke_t": 0.0})
		# 그릴 이름표 (월드 라벨)
		var lbl := _mk_label("🔥 그릴", 13, Color8(0xff, 0xcc, 0x88))
		lbl.position = Vector2(pos.x - 30.0, pos.y - 40.0)
		lbl.size = Vector2(60, 18)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(lbl)


# ── 바닥 장비 추가 (mino1 _addGroundItem) — Main 의 드랍이 호출 ──
func add_ground_item(item: Dictionary) -> void:
	var item_id: String = str(item.get("item_id", ""))
	if not GameData.ITEM_DEFS.has(item_id):
		return
	ground_items.append({"x": float(item.get("x", 0)), "y": float(item.get("y", 0)),
		"item_id": item_id, "t": 0.0})
	var rarity := int(GameData.ITEM_DEFS[item_id].get("rarity", 0))
	var col: Color = GameData.RARITY_TABLE[rarity]["color"]
	var name_short: String = str(GameData.ITEM_DEFS[item_id].get("name", "")).substr(0, 4)
	var lbl := _mk_label(name_short, 11, col)
	lbl.size = Vector2(40, 14)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(lbl)
	_ground_labels.append(lbl)


# ── 날고기 드랍 (mino1 _spawnRawMeat) ──
func add_raw_meat(wx: float, wy: float) -> void:
	if meat_items.size() >= MAX_MEAT_ITEMS:
		return
	meat_items.append({"x": wx, "y": wy, "t": 0.0, "spoil_t": MEAT_SPOIL})


func _process(delta: float) -> void:
	var ts: float = main.time_scale if main else 1.0
	var dt := delta * ts
	if main == null or main.player == null:
		queue_redraw()
		return
	var p: Dictionary = GameState.player
	var pl: Vector2 = main.player.global_position

	_update_ground_items(dt, p, pl)
	_update_meat_items(dt, pl)
	_update_grills(dt, pl, p)
	_update_meat_spoil(dt)

	queue_redraw()


# ── 바닥 장비: 밥 애니 + 소멸 + 자동 줍기 (mino1 _updateGroundItems) ──
func _update_ground_items(dt: float, _p: Dictionary, pl: Vector2) -> void:
	var inv = main.inventory if main else null
	for i in range(ground_items.size() - 1, -1, -1):
		var gi: Dictionary = ground_items[i]
		gi.t += dt
		# 라벨 위치(밥 애니)
		var bob := sin(gi.t * 3.0 + gi.x * 0.01) * 3.0
		if i < _ground_labels.size() and is_instance_valid(_ground_labels[i]):
			var lbl: Label = _ground_labels[i]
			lbl.position = Vector2(gi.x - 20.0, gi.y + bob - 6.0)
			# 20초 임박하면 페이드
			lbl.modulate.a = 1.0 - (gi.t - 16.0) / 4.0 if gi.t > 16.0 else 1.0
		# 소멸
		if gi.t > GROUND_LIFE:
			_remove_ground_item(i)
			continue
		# 자동 줍기 (거리 40 이내)
		var dist := Vector2(gi.x, gi.y).distance_to(pl)
		if dist < GROUND_PICKUP and inv:
			if inv.pickup(str(gi.item_id)):
				_remove_ground_item(i)


func _remove_ground_item(i: int) -> void:
	ground_items.remove_at(i)
	if i < _ground_labels.size():
		var lbl = _ground_labels[i]
		if is_instance_valid(lbl):
			lbl.queue_free()
		_ground_labels.remove_at(i)


# ── 바닥 날고기: 밥 애니 + 상함 + 자동 줍기 (mino1 요리 §1) ──
func _update_meat_items(dt: float, pl: Vector2) -> void:
	for i in range(meat_items.size() - 1, -1, -1):
		var mi: Dictionary = meat_items[i]
		mi.t += dt
		mi.spoil_t -= dt
		# 상함 — 사라짐 (갈색 파티클)
		if mi.spoil_t <= 0.0:
			if main and main.fx:
				main.fx.add_particles(Vector2(mi.x, mi.y), Color8(0x8b, 0x45, 0x13), 5)
			meat_items.remove_at(i)
			continue
		# 자동 줍기 (거리 44 이내)
		var dist := Vector2(mi.x, mi.y).distance_to(pl)
		if dist < MEAT_PICKUP:
			raw_meat += 1
			if main and main.fx:
				main.fx.add_particles(Vector2(mi.x, mi.y), Color8(0xcc, 0x33, 0x33), 6)
			if main:
				main.show_pickup_toast("날고기 획득! 🥩")
			meat_items.remove_at(i)


# ── 그릴: 근처 + 날고기 보유 → 자동 굽기 (mino1 요리 §2) ──
func _update_grills(dt: float, pl: Vector2, _p: Dictionary) -> void:
	cook_msg = ""
	for gr in grills:
		var dist_to := Vector2(gr.x, gr.y).distance_to(pl)
		var near := dist_to < GRILL_NEAR
		# 날고기 있고 + 그릴 근처 + 안 굽는 중 → 굽기 시작
		if near and raw_meat > 0 and not gr.cooking:
			gr.cooking = true
			gr.cook_t = 0.0
			raw_meat -= 1
			if main:
				main.show_pickup_toast("굽기 시작! 잠깐 기다려…")
		if gr.cooking:
			gr.cook_t += dt
			gr.smoke_t += dt
			var prog := minf(1.0, gr.cook_t / COOK_TIME)
			# 굽기 완료 → 구운고기 +1
			if gr.cook_t >= COOK_TIME:
				gr.cooking = false
				gr.cook_t = 0.0
				cooked_meat += 1
				if main and main.fx:
					main.fx.add_particles(Vector2(gr.x, gr.y), Color8(0xff, 0x88, 0x00), 10)
				if main:
					main.show_pickup_toast("구운고기 완성! 먹어서 회복하자!")
			elif dist_to < GRILL_NEAR:
				cook_msg = "굽는 중… %d%%" % int(prog * 100.0)


# ── 보유 날고기/구운고기 상함 타이머 (mino1 요리 §3) ──
func _update_meat_spoil(dt: float) -> void:
	_meat_spoil_timer += dt
	if _meat_spoil_timer >= MEAT_SPOIL:
		_meat_spoil_timer = 0.0
		if cooked_meat > 0:
			cooked_meat -= 1
			if main:
				main.show_meat_alert("구운고기가 상했다!")
		if raw_meat > 0:
			raw_meat -= 1
			if main:
				main.show_meat_alert("날고기가 상했다!")


# ── 구운고기 먹기 (mino1 _eatCookedMeat) — 위기일수록 더 회복 + 짧은 버프 ──
func eat_cooked_meat() -> void:
	if cooked_meat <= 0:
		if main:
			main.show_meat_alert("구운고기 없음! 먼저 구워야지!")
		return
	var p: Dictionary = GameState.player
	cooked_meat -= 1
	# 위기 보정 회복: 체력 40% 미만이면 45, 아니면 30 (mino1)
	var low_hp := float(p.get("hp", 0)) < float(p.get("maxhp", 1)) * 0.4
	var hp_gain := 45.0 if low_hp else 30.0
	var mp_gain := 20.0
	var prev_hp := float(p.get("hp", 0))
	var prev_mp := float(p.get("mp", 0))
	p["hp"] = minf(float(p.get("maxhp", 0)), prev_hp + hp_gain)
	p["mp"] = minf(float(p.get("maxmp", 0)), prev_mp + mp_gain)
	var actual_hp := int(float(p["hp"]) - prev_hp)
	var actual_mp := int(float(p["mp"]) - prev_mp)

	# 짧은 버프 신호 (Main 이 있으면 전달 — 버프 시스템은 S5/S6, 지금은 회복만)
	if main and main.has_method("apply_food_buff"):
		main.apply_food_buff(4.0)

	# 회복 이펙트 + 텍스트
	if main and main.fx and main.player:
		var pl: Vector2 = main.player.global_position
		main.fx.add_particles(pl, Color8(0xff, 0x88, 0x00), 10)
		main.fx.add_particles(pl, Color8(0x4c, 0xdd, 0x88), 8)
		if low_hp:
			main.fx.add_particles(pl, Color8(0xff, 0xdd, 0x44), 8)
		if actual_hp > 0:
			main.spawn_heal_text(pl + Vector2(-20.0, -30.0), "+%d HP" % actual_hp, Color8(0x4c, 0xdd, 0x88))
		if actual_mp > 0:
			main.spawn_heal_text(pl + Vector2(20.0, -30.0), "+%d MP" % actual_mp, Color8(0x44, 0xaa, 0xff))


func _draw() -> void:
	# ── 바닥 장비 (희귀도 테두리 둥근 사각) ──
	for gi in ground_items:
		var item_id: String = str(gi.item_id)
		if not GameData.ITEM_DEFS.has(item_id):
			continue
		var bob := sin(gi.t * 3.0 + gi.x * 0.01) * 3.0
		var cx := float(gi.x)
		var cy := float(gi.y) + bob
		var alpha: float = 1.0 - (gi.t - 16.0) / 4.0 if gi.t > 16.0 else 1.0
		alpha = clampf(alpha, 0.0, 1.0)
		var rarity := int(GameData.ITEM_DEFS[item_id].get("rarity", 0))
		var border: Color = GameData.RARITY_TABLE[rarity]["border"]
		border.a = alpha
		var fill := Color8(0x1e, 0x2a, 0x18, int(0xe6 * alpha))
		var box := Rect2(cx - 18.0, cy - 18.0, 36.0, 36.0)
		draw_rect(box, fill, true)
		_rect_outline(box, border, 2.0)

	# ── 바닥 날고기 ──
	for mi in meat_items:
		var bob := sin(mi.t * 3.0 + mi.x * 0.01) * 3.0
		var cx := float(mi.x)
		var cy := float(mi.y) + bob
		var alpha := 1.0
		if mi.spoil_t < 10.0:
			alpha = 0.5 + 0.5 * abs(sin(mi.t * 5.0))
		_draw_raw_meat(cx, cy, alpha)

	# ── 그릴 + 굽기 연출 ──
	for gr in grills:
		_draw_grill(float(gr.x), float(gr.y))
		if gr.cooking:
			_draw_cooking(gr)


# 날고기 아이콘 (mino1 _drawRawMeatIcon)
func _draw_raw_meat(cx: float, cy: float, alpha: float) -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 그림자
	draw_circle(Vector2(cx + 2.0, cy + 9.0), 8.0, Color(0, 0, 0, 0.22 * alpha))
	# 몸통 (타원 근사 = 원)
	_draw_ellipse(cx, cy, 20.0, 14.0, Color8(0xcc, 0x33, 0x33, int(0xff * alpha)))
	_draw_ellipse(cx - 3.0, cy - 3.0, 10.0, 8.0, Color8(0xdd, 0x55, 0x44, int(0xcc * alpha)))
	# 뼈대 흰 부분
	draw_circle(Vector2(cx + 7.0, cy - 4.0), 4.0, Color(1, 1, 1, 0.7 * alpha))
	draw_circle(Vector2(cx + 7.0, cy + 4.0), 3.0, Color(1, 1, 1, 0.7 * alpha))


# 그릴 모양 (mino1 _drawGrill)
func _draw_grill(cx: float, cy: float) -> void:
	# 다리
	draw_rect(Rect2(cx - 20.0, cy + 10.0, 5.0, 18.0), Color8(0x44, 0x44, 0x44))
	draw_rect(Rect2(cx + 15.0, cy + 10.0, 5.0, 18.0), Color8(0x44, 0x44, 0x44))
	# 본체 (타원)
	_draw_ellipse(cx, cy, 56.0, 28.0, Color8(0x2a, 0x2a, 0x2a))
	_draw_ellipse(cx - 6.0, cy - 4.0, 32.0, 12.0, Color8(0x44, 0x44, 0x44, 0x99))
	# 테두리
	_draw_ellipse_outline(cx, cy, 56.0, 28.0, Color8(0x88, 0x88, 0x88), 2.5)
	# 격자 막대
	var i := -16.0
	while i <= 16.0:
		draw_line(Vector2(cx + i, cy - 8.0), Vector2(cx + i, cy + 8.0), Color8(0x66, 0x66, 0x66, 0xe6), 2.0)
		i += 8.0
	draw_line(Vector2(cx - 20.0, cy - 3.0), Vector2(cx + 20.0, cy - 3.0), Color8(0x55, 0x55, 0x55, 0xb3), 1.5)
	draw_line(Vector2(cx - 20.0, cy + 3.0), Vector2(cx + 20.0, cy + 3.0), Color8(0x55, 0x55, 0x55, 0xb3), 1.5)
	# 불빛
	_draw_ellipse(cx, cy + 6.0, 50.0, 22.0, Color(1.0, 0.4, 0.0, 0.18))


# 굽기 연출 (연기 + 진행 원호 + 익는 고기) (mino1 요리 §2 그리기 부분)
func _draw_cooking(gr: Dictionary) -> void:
	var cx := float(gr.x)
	var cy := float(gr.y)
	var prog := minf(1.0, gr.cook_t / COOK_TIME)
	# 연기 (회색 원 여러 개)
	var num_smoke := 2 + int(prog * 3.0)
	for s in num_smoke:
		var sx := cx + (randf() - 0.5) * 24.0
		var sy := cy - 18.0 - s * 10.0
		var s_alpha := (0.4 - prog * 0.1) * (0.5 + 0.5 * sin(gr.smoke_t * 3.0 + s))
		draw_circle(Vector2(sx, sy), 5.0 + s * 2.0, Color(0.667, 0.667, 0.667, maxf(0.05, s_alpha)))
	# 진행 원호 (그릴 위)
	var bar_r := 12.0
	var bar_c := Vector2(cx, cy - 28.0)
	draw_arc(bar_c, bar_r, 0.0, TAU, 32, Color(0.2, 0.2, 0.2, 0.6), 3.0)
	var start_a := -PI / 2.0
	var end_a := start_a + prog * TAU
	draw_arc(bar_c, bar_r, start_a, end_a, 32, Color(1.0, 0.533, 0.0, 0.95), 3.0)
	# 익는 고기 색 (빨강 → 갈색 → 진갈색)
	var meat_col: Color
	if prog < 0.5:
		meat_col = Color8(0xcc, 0x33, 0x33).lerp(Color8(0x8b, 0x45, 0x13), prog * 2.0)
	else:
		meat_col = Color8(0x8b, 0x45, 0x13).lerp(Color8(0x5a, 0x2a, 0x00), (prog - 0.5) * 2.0)
	_draw_ellipse(cx, cy, 22.0, 12.0, meat_col)


# ── 작은 그리기 헬퍼 (Godot 엔 fillEllipse 가 없어 직접) ──
func _draw_ellipse(cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var n := 24
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	draw_colored_polygon(pts, col)


func _draw_ellipse_outline(cx: float, cy: float, rx: float, ry: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	var n := 28
	for i in n + 1:
		var a := TAU * float(i) / float(n)
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	draw_polyline(pts, col, w, true)


func _rect_outline(r: Rect2, col: Color, w: float) -> void:
	var pts := PackedVector2Array([
		r.position, Vector2(r.position.x + r.size.x, r.position.y),
		Vector2(r.position.x + r.size.x, r.position.y + r.size.y),
		Vector2(r.position.x, r.position.y + r.size.y), r.position])
	draw_polyline(pts, col, w, true)


func _mk_label(txt: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	if kfont:
		l.add_theme_font_override("font", kfont)
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 3)
	l.text = txt
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
