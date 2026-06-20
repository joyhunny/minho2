extends Node2D
class_name TerrainSystem
## TerrainSystem — 지역별 지형(바위 장애물·독 웅덩이·버프 크리스탈)과 그 효과.
## mino1 play.js 의 _initTerrainZones / _updateTerrainEffects 1:1 대응.
##
## 지역(REGION_DEFS)마다 바위/독/버프 개수·이동배율·바위색·엘리트율이 다르다.
## - 바위: 통과 못 함(밀어냄). 보스 돌진이 박으면 기절(보스 패턴이 참조).
## - 독 웅덩이: 안에 있으면 초당 6 피해 + 화면 가장자리 초록 비네팅.
## - 버프 크리스탈: 안에 있으면 공격력 +30%·이속 +25% (벗어나도 3초 유지).
## 밸런스 숫자(개수·반경·피해·이동배율·버프 배수)는 mino1 값을 그대로 보존한다.
##
## 월드 좌표 Node2D 라서 바위·독·버프를 직접 _draw 로 그린다. 효과 판정은 Main 이 매 프레임 update(dt) 호출.

var main: Node = null

# ── 지역 규칙 (REGION_DEFS 에서 읽어옴) ──────────────────────
var region_move_mult := 1.0    # 이동 배율 (늪=0.72 등) — Player 가 참조
var region_elite_rate := 0.08  # 엘리트 등장 확률 — Main._spawn_enemy 가 참조
var rock_color := Color8(0x4a, 0x50, 0x40)

# ── 지형 배치 (mino1 _poisonPools/_obstacles/_buffZones) ────
var poison_pools: Array = []   # [{x, y, rx, ry}]
var obstacles: Array = []      # [{x, y, r}] — 보스 돌진 충돌이 참조
var buff_zones: Array = []     # [{x, y, r}]

# ── 효과 상태 (mino1 _poisonActive/_buffActive/_buffTimer) ──
var poison_active := false
var poison_tick_t := 0.0
var buff_active := false
var buff_timer := 0.0
var _vig_t := 0.0              # 비네팅 펄스 위상

var _poison_vig: Node2D = null  # 화면 가장자리 초록 비네팅(화면 고정)
var _buff_label: Label = null   # 버프 HUD 텍스트(화면 고정)


func _ready() -> void:
	# 독 비네팅(화면 고정) + 버프 HUD 라벨은 CanvasLayer 에 올린다
	var layer := CanvasLayer.new()
	layer.name = "TerrainOverlay"
	layer.layer = 6  # info 와 같은 대(HUD 위, 패널 아래)
	add_child(layer)

	_poison_vig = Node2D.new()
	_poison_vig.set_script(_make_vig_script())
	_poison_vig.set("terr", self)
	layer.add_child(_poison_vig)

	_buff_label = Label.new()
	if main and main.has_method("get_kfont") and main.get_kfont():
		_buff_label.add_theme_font_override("font", main.get_kfont())
	_buff_label.add_theme_font_size_override("font_size", 16)
	_buff_label.add_theme_color_override("font_color", Color8(0xee, 0x88, 0xff))
	_buff_label.add_theme_color_override("font_outline_color", Color8(0x1a, 0x1a, 0x1a))
	_buff_label.add_theme_constant_override("outline_size", 4)
	_buff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_buff_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buff_label.visible = false
	layer.add_child(_buff_label)

	init_zones()


# ── 지역 지형 재생성 (mino1 _initTerrainZones) ──────────────
# 지역마다 다른 시드 → 들판/늪/폐허/성이 서로 다른 모양. 재입장 시 다시 깐다.
func init_zones() -> void:
	var region: int = clampi(GameState.region, 0, GameData.REGION_DEFS.size() - 1)
	var def: Dictionary = GameData.REGION_DEFS[region]
	var n_poison := int(def.get("poison", 12))
	var n_rocks := int(def.get("rocks", 12))
	var n_buffs := int(def.get("buffs", 2))
	rock_color = def.get("rock_color", Color8(0x4a, 0x50, 0x40))
	region_move_mult = float(def.get("move_mult", 1.0))
	region_elite_rate = float(def.get("elite_rate", 0.08))

	# 지역마다 다른 배치 시드 (mino1: 3141 + region*777)
	var rng := GameData.make_rng(3141 + region * 777)
	var start_safe := 200.0
	var sx0 := GameData.WORLD_W / 2.0
	var sy0 := GameData.WORLD_H / 2.0

	poison_pools = []
	obstacles = []
	buff_zones = []

	# ── ① 독 웅덩이 (지역별 개수) ──
	var tries := 0
	while poison_pools.size() < n_poison and tries < 300:
		tries += 1
		var x := rng.range_f(80.0, GameData.WORLD_W - 80.0)
		var y := rng.range_f(80.0, GameData.WORLD_H - 80.0)
		if Vector2(x - sx0, y - sy0).length() < start_safe:
			continue
		var too_close := false
		for po in poison_pools:
			if Vector2(po.x - x, po.y - y).length() < 110.0:
				too_close = true
				break
		if too_close:
			continue
		var rx := rng.range_f(30.0, 58.0)
		var ry := roundf(rx * (0.38 + rng.range_f(0.0, 18.0) / 100.0))
		poison_pools.append({"x": x, "y": y, "rx": rx, "ry": ry})

	# ── ② 바위 장애물 (지역별 개수) ──
	tries = 0
	while obstacles.size() < n_rocks and tries < 400:
		tries += 1
		var x2 := rng.range_f(100.0, GameData.WORLD_W - 100.0)
		var y2 := rng.range_f(100.0, GameData.WORLD_H - 100.0)
		if Vector2(x2 - sx0, y2 - sy0).length() < start_safe:
			continue
		var too_close2 := false
		for o in obstacles:
			if Vector2(o.x - x2, o.y - y2).length() < 90.0:
				too_close2 = true
				break
		if too_close2:
			continue
		var r := rng.range_f(22.0, 36.0)
		obstacles.append({"x": x2, "y": y2, "r": r})

	# ── ③ 버프 크리스탈 (지역별 개수) ──
	tries = 0
	while buff_zones.size() < n_buffs and tries < 100:
		tries += 1
		var x3 := rng.range_f(120.0, GameData.WORLD_W - 120.0)
		var y3 := rng.range_f(120.0, GameData.WORLD_H - 120.0)
		if Vector2(x3 - sx0, y3 - sy0).length() < start_safe:
			continue
		var bad := false
		for o in obstacles:
			if Vector2(o.x - x3, o.y - y3).length() < 80.0:
				bad = true
				break
		for po in poison_pools:
			if Vector2(po.x - x3, po.y - y3).length() < 100.0:
				bad = true
				break
		if bad:
			continue
		buff_zones.append({"x": x3, "y": y3, "r": 48.0})

	# 효과 상태 리셋
	poison_active = false
	poison_tick_t = 0.0
	buff_active = false
	buff_timer = 0.0
	queue_redraw()


# ── 매 프레임 효과 (mino1 _updateTerrainEffects) — Main 이 호출 ──
func update(dt: float) -> void:
	if main == null or main.player == null:
		return
	var p: Dictionary = GameState.player
	var hero: Node2D = main.player
	_vig_t += dt

	# ── ① 바위 충돌 (주인공) — 바깥으로 밀어냄 ──
	for obs in obstacles:
		var ddx: float = hero.global_position.x - obs.x
		var ddy: float = (hero.global_position.y - obs.y) * 1.4   # 타원 보정
		var dist := sqrt(ddx * ddx + ddy * ddy)
		var push_r: float = obs.r * 1.1
		if dist < push_r and dist > 0.0:
			var nx: float = ddx / dist
			var ny: float = (hero.global_position.y - obs.y) / maxf(0.0001, sqrt(ddx * ddx + ddy * ddy))
			var push := push_r - dist
			hero.global_position.x += nx * push * 0.9
			hero.global_position.y += (ny / 1.4) * push * 0.9
			p["x"] = hero.global_position.x
			p["y"] = hero.global_position.y

	# ── 바위 충돌 (적들도) ──
	for obs in obstacles:
		for e in main.enemies:
			if not is_instance_valid(e) or e.dead:
				continue
			var ex: float = e.global_position.x - obs.x
			var ey: float = (e.global_position.y - obs.y) * 1.4
			var ed := sqrt(ex * ex + ey * ey)
			var pr2: float = obs.r * 1.05
			if ed < pr2 and ed > 0.0:
				var nx2: float = ex / ed
				var ny2: float = (e.global_position.y - obs.y) / maxf(0.0001, sqrt(ex * ex + ey * ey))
				var push2 := pr2 - ed
				e.global_position.x += nx2 * push2 * 0.85
				e.global_position.y += (ny2 / 1.4) * push2 * 0.85

	# ── ② 독 웅덩이 판정 + 틱 피해 ──
	poison_active = false
	for po in poison_pools:
		var pdx: float = hero.global_position.x - po.x
		var pdy: float = (hero.global_position.y - po.y) * (po.rx / maxf(1.0, po.ry))
		if sqrt(pdx * pdx + pdy * pdy) < po.rx:
			poison_active = true
			break

	if poison_active:
		poison_tick_t -= dt
		if poison_tick_t <= 0.0:
			poison_tick_t = 1.0
			if not hero.is_invincible():
				main.hazard_damage(6.0, 0.0, Color8(0x44, 0xff, 0x44), "☠")
	else:
		poison_tick_t = maxf(0.0, poison_tick_t - dt)

	# ── ③ 버프 존 판정 ──
	var in_buff := false
	for bz in buff_zones:
		if Vector2(hero.global_position.x - bz.x, hero.global_position.y - bz.y).length() < bz.r:
			in_buff = true
			break
	if in_buff:
		buff_active = true
		buff_timer = 3.0   # 나가도 3초 유지
	elif buff_timer > 0.0:
		buff_timer -= dt
		if buff_timer <= 0.0:
			buff_timer = 0.0
			buff_active = false

	# 버프 HUD
	if _buff_label:
		if buff_active:
			var vp := get_viewport().get_visible_rect().size
			_buff_label.visible = true
			_buff_label.size = Vector2(vp.x, 24)
			_buff_label.position = Vector2(0, 100)
			var secs := int(ceil(buff_timer))
			_buff_label.text = "✦ 크리스탈 버프 — 공격력 +30%  이동속도 +25%  (%d초)" % secs
			_buff_label.modulate.a = 0.9 + 0.1 * sin(_vig_t * 10.0)
		else:
			_buff_label.visible = false

	queue_redraw()


# ── 지형 그리기 (mino1 _poisonGfx/_obstacleGfx/_buffGfx) ────
func _draw() -> void:
	# 독 웅덩이 (독성 녹색 타원)
	for po in poison_pools:
		var c := Vector2(po.x, po.y)
		# 바깥 발광 링
		draw_arc(c, (po.rx + 5.0), 0.0, TAU, 28, Color(0.27, 1.0, 0.27, 0.55), 3.0)
		# 본체
		_draw_ellipse(c, po.rx, po.ry, Color(0.10, 0.36, 0.10, 0.62))
		# 내부 반사
		_draw_ellipse(Vector2(po.x - po.rx * 0.15, po.y - po.ry * 0.2), po.rx * 0.5, po.ry * 0.4, Color(0.4, 1.0, 0.4, 0.22))

	# 바위 (지역별 색)
	for obs in obstacles:
		var r: float = obs.r
		var oc := Vector2(obs.x, obs.y)
		# 그림자
		_draw_ellipse(Vector2(obs.x + 5.0, obs.y + r * 0.6), r * 1.4, r * 0.45, Color(0, 0, 0, 0.30))
		# 본체
		_draw_ellipse(oc, r * 1.1, r * 0.9, rock_color)
		# 상단 하이라이트
		_draw_ellipse(Vector2(obs.x - r * 0.2, obs.y - r * 0.3), r * 0.6, r * 0.35, Color(0.48, 0.5, 0.44, 0.7))
		# 이끼
		_draw_ellipse(Vector2(obs.x + r * 0.15, obs.y), r * 0.4, r * 0.25, Color(0.23, 0.35, 0.16, 0.6))
		# 테두리 (막힘 표시)
		draw_arc(oc, r * 1.1, 0.0, TAU, 24, Color(0.87, 0.8, 0.53, 0.55), 2.0)

	# 버프 크리스탈 (보라 발광 원)
	for bz in buff_zones:
		var c2 := Vector2(bz.x, bz.y)
		draw_arc(c2, bz.r + 8.0, 0.0, TAU, 32, Color(0.8, 0.27, 1.0, 0.5), 4.0)
		draw_circle(c2, bz.r, Color(0.35, 0.04, 0.55, 0.38))
		draw_circle(c2, bz.r * 0.6, Color(0.67, 0.27, 1.0, 0.25))
		draw_circle(c2, bz.r * 0.2, Color(0.87, 0.53, 1.0, 0.45))
		draw_arc(c2, bz.r, 0.0, TAU, 28, Color(0.93, 0.53, 1.0, 0.7), 2.0)


# 타원 채우기 (Godot 엔 draw_ellipse 가 없어 스케일 변환으로)
func _draw_ellipse(center: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var n := 24
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


# 화면 가장자리 독 비네팅을 그리는 Node2D 스크립트 (화면 고정)
func _make_vig_script() -> GDScript:
	var src := """
extends Node2D
var terr
func _process(_d):
	queue_redraw()
func _draw():
	if terr == null or not terr.poison_active:
		return
	var vp = get_viewport().get_visible_rect().size
	var pulse = 0.18 + 0.08 * sin(terr._vig_t * 5.0)
	var c = Color(0.0, 0.67, 0.13, pulse)
	var t = 28.0
	draw_rect(Rect2(0, 0, vp.x, t), c, true)
	draw_rect(Rect2(0, vp.y - t, vp.x, t), c, true)
	draw_rect(Rect2(0, 0, t, vp.y), c, true)
	draw_rect(Rect2(vp.x - t, 0, t, vp.y), c, true)
"""
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s
