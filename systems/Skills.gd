extends Node2D
class_name SkillSystem
## SkillSystem — 스킬 엔진. mino1 play.js 의 스킬 부분을 통째로 옮긴 것.
## 기본 스킬 6종(파이어볼·메테오·순간이동·무적·워터폴·소환) + 전직 클래스 스킬 12종.
## 쿨다운·마나·투사체(파이어볼/표창)·메테오·워터폴 장판·소환 슬라임·화면 플래시를 담당한다.
## 월드 좌표 Node2D 라서 투사체·장판·메테오·플래시를 직접 _draw 로 그린다.
## 밸런스 숫자(마나·쿨·데미지 배수)는 mino1 값을 그대로 보존한다.
##
## Main 이 _ready 에서 main 참조를 넣고, _process 에서 update(dt) 를 부른다.
## SkillTray·SkillMenu(UI) 가 cast_skill(key) / cast_class_skill(def) 을 호출한다.

var main: Node = null

# ── 기본 스킬 6종 (mino1 this._skills) — cd·maxCd·mpCost 보존 ──
var skills := {
	"fireball":    {"cd": 0.0, "max_cd": 2.0,  "mp_cost": 20.0},
	"meteor":      {"cd": 0.0, "max_cd": 6.0,  "mp_cost": 35.0},
	"teleport":    {"cd": 0.0, "max_cd": 4.0,  "mp_cost": 15.0},
	"invincible":  {"cd": 0.0, "max_cd": 10.0, "mp_cost": 0.0},
	"waterfall":   {"cd": 0.0, "max_cd": 5.0,  "mp_cost": 25.0},
	"summon_ally": {"cd": 0.0, "max_cd": 12.0, "mp_cost": 30.0},
}

# 전직 클래스 스킬 쿨다운 (mino1 this._ultCd) — {key: 남은 쿨}
var ult_cd := {}

# 발사체·메테오·장판·소환 슬라임 (mino1 배열들)
var fireballs: Array = []      # {pos, vel, t, life, exploded, exp_t, kind}
var skill_meteors: Array = []  # {tx, ty, warn_t, falling, fall_y, hit, hit_t}
var waterfalls: Array = []     # {pos, face, t, life, tick_t, w, h, dmg_mult, time_label}
var ally_slimes: Array = []    # {node, atk_timer}

# 무적 스킬 (mino1 _invincibleT)
var invincible_t := 0.0

# 화면 전체 플래시 (mino1 _flashColor/_flashT) — Main 의 CanvasLayer 오버레이로 표시
var flash_color := Color.WHITE
var flash_t := 0.0
var flash_max := 0.22
var flash_strength := 0.0

const ALLY_SLIME_BASE_ATK := 12.0   # mino1 _allySlimeBaseAtk

# 클래스 스킬 정의 (mino1 _classSkills) — 1·2차 전직별
const CLASS_SKILLS := {
	# ── 1차 전직 전용 (Lv10) ──
	"mage": [
		{"key": "frost_nova",   "name": "빙결 폭발",   "icon": "❄️", "mp": 28.0, "cd": 5.0, "color": Color8(0x66, 0xcc, 0xff), "desc": "주변 적을 얼음으로 강타"},
		{"key": "chain_bolt",   "name": "번개 사슬",   "icon": "⚡", "mp": 32.0, "cd": 6.0, "color": Color8(0x88, 0xdd, 0xff), "desc": "가까운 적들을 연쇄로 친다"},
		{"key": "flame_pillar", "name": "화염 기둥",   "icon": "🔥", "mp": 38.0, "cd": 7.0, "color": Color8(0xff, 0x77, 0x33), "desc": "전방에 거대한 불기둥"},
	],
	"warrior": [
		{"key": "crush_blow",  "name": "분쇄 강타",   "icon": "💥", "mp": 24.0, "cd": 4.5, "color": Color8(0xff, 0xcc, 0x44), "desc": "전방을 내리쳐 밀쳐낸다"},
		{"key": "earth_split", "name": "대지 가르기", "icon": "🌋", "mp": 34.0, "cd": 6.5, "color": Color8(0xdd, 0x88, 0x44), "desc": "땅을 갈라 직선상 적 강타"},
	],
	"rogue": [
		{"key": "poison_fan",    "name": "독칼 난무",   "icon": "🗡️", "mp": 24.0, "cd": 4.0, "color": Color8(0x88, 0xdd, 0x66), "desc": "부채꼴로 독칼을 뿌린다"},
		{"key": "shadow_strike", "name": "그림자 일격", "icon": "🌑", "mp": 30.0, "cd": 5.5, "color": Color8(0x99, 0x66, 0xdd), "desc": "파고들어 치명타를 꽂는다"},
	],
	# ── 2차 전직 전용 (Lv25) ──
	"swordmaster": [
		{"key": "blade_wave", "name": "검기 베기", "icon": "🌀", "mp": 30.0, "cd": 4.0, "color": Color8(0xff, 0x66, 0xcc), "desc": "전방으로 거대한 검기를 날린다"},
		{"key": "whirl",      "name": "회전 베기", "icon": "⚔️", "mp": 40.0, "cd": 6.0, "color": Color8(0xff, 0x99, 0xdd), "desc": "주변을 한 바퀴 휩쓸어 벤다"},
	],
	"archmage": [
		{"key": "meteor_storm", "name": "유성우",   "icon": "☄️", "mp": 50.0, "cd": 9.0, "color": Color8(0x66, 0xcc, 0xff), "desc": "하늘에서 유성 다섯 개를 떨군다"},
		{"key": "arcane_nova",  "name": "비전 폭발", "icon": "💥", "mp": 45.0, "cd": 7.0, "color": Color8(0x99, 0xdd, 0xff), "desc": "화면 전체에 마법 폭발"},
	],
	"ninja": [
		{"key": "shuriken_storm", "name": "표창 난사",   "icon": "✴️", "mp": 25.0, "cd": 3.0, "color": Color8(0x88, 0xff, 0xcc), "desc": "표창을 부채꼴로 난사한다"},
		{"key": "shadow_dash",    "name": "그림자 질주", "icon": "🥷", "mp": 30.0, "cd": 5.0, "color": Color8(0x44, 0xdd, 0xaa), "desc": "순식간에 가로지르며 모두 벤다"},
	],
}


func _process(_delta: float) -> void:
	queue_redraw()


# ════════════════════════════════════════════════════════════
#  매 프레임 갱신 (mino1 _updateSkills) — Main._process 가 dt 로 호출
# ════════════════════════════════════════════════════════════
func update(dt: float) -> void:
	var p: Dictionary = GameState.player

	# 쿨타임 감소 (대마법사는 30% 빠르게 = 1.3배 속도)
	var cd_speed := 1.3 if p.get("job2", null) == "archmage" else 1.0
	for k in skills.keys():
		if skills[k]["cd"] > 0.0:
			skills[k]["cd"] = maxf(0.0, skills[k]["cd"] - dt * cd_speed)
	for k in ult_cd.keys():
		if ult_cd[k] > 0.0:
			ult_cd[k] = maxf(0.0, ult_cd[k] - dt * cd_speed)

	# 화면 플래시 페이드
	if flash_t > 0.0:
		flash_t -= dt
		if flash_t < 0.0:
			flash_t = 0.0

	# 마법사 계열 추가 마나 회복 (대마법사 더 빠르게) (mino1)
	if p.get("job2", null) == "archmage":
		p["mp"] = minf(float(p["maxmp"]), float(p["mp"]) + 18.0 * dt)
	elif p.get("job", null) == "mage":
		p["mp"] = minf(float(p["maxmp"]), float(p["mp"]) + 10.0 * dt)

	# 무적 스킬 타이머 (mino1 _invincibleT)
	if invincible_t > 0.0:
		invincible_t -= dt
		# 무적 중엔 피격 무적도 유지
		p["inv"] = maxf(float(p.get("inv", 0.0)), 0.1)
		if invincible_t < 0.0:
			invincible_t = 0.0

	_update_fireballs(dt)
	_update_meteors(dt)
	_update_waterfalls(dt)
	_update_ally_slimes(dt)


# ════════════════════════════════════════════════════════════
#  스킬 발동 (mino1 _castSkill)
# ════════════════════════════════════════════════════════════
func cast_skill(key: String) -> void:
	var p: Dictionary = GameState.player
	if not skills.has(key):
		return
	var sk: Dictionary = skills[key]
	if sk["cd"] > 0.0:
		_feedback("쿨타임!", Color8(0xff, 0x44, 0x44))
		return

	# 무적 스킬은 특별 조건: 현재 마나 전부 소모 (maxmp 300 이상이면 300 기준)
	if key == "invincible":
		var threshold := 300.0 if float(p["maxmp"]) >= 300.0 else float(p["maxmp"])
		if float(p["mp"]) < threshold:
			_feedback("마나 부족!", Color8(0x44, 0x88, 0xff))
			return
		p["mp"] = 0.0
	else:
		if float(p["mp"]) < float(sk["mp_cost"]):
			_feedback("마나 부족!", Color8(0x44, 0x88, 0xff))
			return
		p["mp"] = float(p["mp"]) - float(sk["mp_cost"])

	sk["cd"] = sk["max_cd"]

	match key:
		"fireball":    _cast_fireball()
		"meteor":      _cast_meteor()
		"teleport":    _cast_teleport()
		"invincible":  _cast_invincible()
		"waterfall":   _cast_waterfall()
		"summon_ally": _cast_summon_ally()


# ── 발동 가능 여부 (SkillTray 가 색·아이콘에 사용) ──
func can_cast(key: String) -> bool:
	var p: Dictionary = GameState.player
	if not skills.has(key):
		return false
	var sk: Dictionary = skills[key]
	if sk["cd"] > 0.0:
		return false
	if key == "invincible":
		var threshold := 300.0 if float(p["maxmp"]) >= 300.0 else float(p["maxmp"])
		return float(p["mp"]) >= threshold
	return float(p["mp"]) >= float(sk["mp_cost"])


# ── 클래스(전직) 스킬 위력 배수 (mino1 _skillDmgMult) ──
func skill_dmg_mult() -> float:
	var p: Dictionary = GameState.player
	if p.get("job2", null) == "archmage":
		return 2.6
	if p.get("job2", null) == "swordmaster":
		return 1.6
	if p.get("job", null) == "mage":
		return 1.8
	return 1.0


# ── 현재 직업이 쓸 수 있는 클래스 스킬 목록 (mino1 _myClassSkills) ──
func my_class_skills() -> Array:
	var p: Dictionary = GameState.player
	var list: Array = []
	var job = p.get("job", null)
	var job2 = p.get("job2", null)
	if job != null and CLASS_SKILLS.has(job):
		list.append_array(CLASS_SKILLS[job])
	if job2 != null and CLASS_SKILLS.has(job2):
		list.append_array(CLASS_SKILLS[job2])
	return list


# ── 클래스 스킬 발동 (mino1 _castClassSkill) — 성공 시 true ──
func cast_class_skill(def: Dictionary) -> bool:
	var p: Dictionary = GameState.player
	var key: String = def["key"]
	if float(ult_cd.get(key, 0.0)) > 0.0:
		_feedback("쿨타임!", Color8(0xff, 0x44, 0x44))
		return false
	if float(p["mp"]) < float(def["mp"]):
		_feedback("마나 부족!", Color8(0x44, 0x88, 0xff))
		return false
	p["mp"] = float(p["mp"]) - float(def["mp"])
	ult_cd[key] = float(def["cd"])
	match key:
		"blade_wave":     _cast_blade_wave()
		"whirl":          _cast_whirl()
		"meteor_storm":   _cast_meteor_storm()
		"arcane_nova":    _cast_arcane_nova()
		"shuriken_storm": _cast_shuriken_storm()
		"shadow_dash":    _cast_shadow_dash()
		"frost_nova":     _cast_frost_nova()
		"chain_bolt":     _cast_chain_bolt()
		"flame_pillar":   _cast_flame_pillar()
		"crush_blow":     _cast_crush_blow()
		"earth_split":    _cast_earth_split()
		"poison_fan":     _cast_poison_fan()
		"shadow_strike":  _cast_shadow_strike()
	return true


# ════════════════════════════════════════════════════════════
#  기본 스킬 발동부 (mino1 _cast*)
# ════════════════════════════════════════════════════════════
func _cast_fireball() -> void:
	var pl: Node2D = main.player
	var face: int = pl.face
	fireballs.append({
		"pos": pl.global_position, "vel": Vector2(face * 320.0, 0.0),
		"t": 0.0, "life": 2.5, "exploded": false, "exp_t": 0.0, "kind": "fireball",
	})


func _cast_meteor() -> void:
	var pl: Node2D = main.player
	var p: Dictionary = GameState.player
	var face: int = pl.face
	var tx := pl.global_position.x + face * 180.0
	var ty := pl.global_position.y
	var near = _nearest_enemy()
	if near != null:
		tx = near.global_position.x
		ty = near.global_position.y
	tx = clampf(tx, 40.0, GameData.WORLD_W - 40.0)
	ty = clampf(ty, 40.0, GameData.WORLD_H - 40.0)
	skill_meteors.append({"tx": tx, "ty": ty, "warn_t": 1.2, "falling": false,
		"fall_y": ty - 500.0, "hit": false, "hit_t": 0.0})


func _cast_teleport() -> void:
	var pl: Node2D = main.player
	var p: Dictionary = GameState.player
	var dist := 180.0
	var nx := clampf(pl.global_position.x + pl.face * dist, 40.0, GameData.WORLD_W - 40.0)
	var ny := clampf(pl.global_position.y, 40.0, GameData.WORLD_H - 40.0)
	main.fx.add_particles(pl.global_position, Color8(0x88, 0x88, 0xff), 12)
	pl.global_position = Vector2(nx, ny)
	p["x"] = nx
	p["y"] = ny
	main.fx.add_particles(Vector2(nx, ny), Color8(0xaa, 0xaa, 0xff), 12)
	p["inv"] = 0.3


func _cast_invincible() -> void:
	invincible_t = 3.0
	var pl: Node2D = main.player
	# 발동 시 주변 적을 밀어낸다 (mino1)
	for e in main.enemies:
		if not is_instance_valid(e) or e.dead:
			continue
		var d: Vector2 = e.global_position - pl.global_position
		var dl := d.length()
		if dl < 0.5:
			dl = 1.0
		if dl < 170.0:
			e.velocity += (d / dl) * 440.0
	main.spawn_impact(pl.global_position, 150.0, Color8(0xff, 0xdd, 0x44))
	main.fx.add_particles(pl.global_position, Color8(0xff, 0xdd, 0x44), 20)
	trigger_flash(Color8(0xff, 0xdd, 0x44), 0.22)
	main.add_shake(0.18, 6.0)


func _cast_waterfall() -> void:
	var pl: Node2D = main.player
	var face: int = pl.face
	waterfalls.append({
		"pos": Vector2(pl.global_position.x + face * 80.0, pl.global_position.y),
		"face": face, "t": 0.0, "life": 2.5, "tick_t": 0.0,
		"w": 60.0, "h": 110.0, "dmg_mult": skill_dmg_mult(), "time_label": null,
	})
	main.fx.add_particles(Vector2(pl.global_position.x + face * 80.0, pl.global_position.y), Color8(0x44, 0xaa, 0xff), 10)


func _cast_summon_ally() -> void:
	var pl: Node2D = main.player
	if ally_slimes.size() >= 3:
		_feedback("동료 최대 3마리!", Color8(0x55, 0xcc, 0x88))
		# 마나·쿨 돌려줌 (mino1)
		GameState.player["mp"] = float(GameState.player["mp"]) + float(skills["summon_ally"]["mp_cost"])
		skills["summon_ally"]["cd"] = 0.0
		return
	_spawn_ally_slime(pl.global_position.x + (randf() - 0.5) * 60.0, pl.global_position.y + (randf() - 0.5) * 60.0)
	main.fx.add_particles(pl.global_position, Color8(0x55, 0xcc, 0x88), 12)


# ════════════════════════════════════════════════════════════
#  클래스 스킬 발동부 (mino1 1·2차 전직 전용 스킬)
# ════════════════════════════════════════════════════════════
# 마검사 — 검기 베기: 전방 부채꼴 큰 데미지
func _cast_blade_wave() -> void:
	var pl: Node2D = main.player
	var p: Dictionary = GameState.player
	var dmg := roundf(float(p["atkPow"]) * 2.2 * skill_dmg_mult())
	var face: int = pl.face
	var cx := pl.global_position.x + face * 90.0
	for e in main.enemies:
		if not is_instance_valid(e) or e.dead or e.hp <= 0.0:
			continue
		var ep: Vector2 = e.global_position
		var ddx := ep.x - pl.global_position.x
		var ddy := ep.y - pl.global_position.y
		if ddx * face >= -20.0 and sqrt(ddx * ddx + ddy * ddy) < 200.0:
			_hit_enemy(e, dmg, false, Color8(0xff, 0x66, 0xcc), 6)
	pl.slash_t = 0.3
	main.spawn_impact(Vector2(cx, pl.global_position.y), 150.0, Color8(0xff, 0x66, 0xcc))
	main.fx.add_particles(Vector2(cx, pl.global_position.y), Color8(0xff, 0x99, 0xdd), 18)
	trigger_flash(Color8(0xff, 0x66, 0xcc), 0.28)
	main.hitstop_t = 0.06


# 마검사 — 회전 베기: 주변 360도
func _cast_whirl() -> void:
	var pl: Node2D = main.player
	var p: Dictionary = GameState.player
	var dmg := roundf(float(p["atkPow"]) * 1.8 * skill_dmg_mult())
	_aoe_damage(pl.global_position, 160.0, dmg, Color8(0xff, 0x99, 0xdd))
	main.spawn_impact(pl.global_position, 160.0, Color8(0xff, 0x66, 0xcc))
	main.spawn_impact(pl.global_position, 110.0, Color.WHITE)
	main.fx.add_particles(pl.global_position, Color8(0xff, 0x66, 0xcc), 24)
	trigger_flash(Color8(0xff, 0x99, 0xdd), 0.3)
	main.hitstop_t = 0.07


# 대마법사 — 유성우: 유성 5개
func _cast_meteor_storm() -> void:
	var pl: Node2D = main.player
	for i in 5:
		var tx := pl.global_position.x + (randf() - 0.5) * 360.0
		var ty := pl.global_position.y + (randf() - 0.5) * 360.0
		if i == 0:
			var near = _nearest_enemy()
			if near != null:
				tx = near.global_position.x
				ty = near.global_position.y
		tx = clampf(tx, 40.0, GameData.WORLD_W - 40.0)
		ty = clampf(ty, 40.0, GameData.WORLD_H - 40.0)
		skill_meteors.append({"tx": tx, "ty": ty, "warn_t": 0.6 + i * 0.18, "falling": false,
			"fall_y": ty - 500.0, "hit": false, "hit_t": 0.0})
	trigger_flash(Color8(0x66, 0xcc, 0xff), 0.22)


# 대마법사 — 비전 폭발: 화면 전체 대폭발
func _cast_arcane_nova() -> void:
	var pl: Node2D = main.player
	var p: Dictionary = GameState.player
	var dmg := roundf(float(p["atkPow"]) * 2.0 * skill_dmg_mult())
	_aoe_damage(pl.global_position, 360.0, dmg, Color8(0x99, 0xdd, 0xff))
	main.spawn_impact(pl.global_position, 340.0, Color8(0x66, 0xcc, 0xff))
	main.spawn_impact(pl.global_position, 230.0, Color8(0x99, 0xdd, 0xff))
	main.spawn_impact(pl.global_position, 130.0, Color.WHITE)
	main.fx.add_particles(pl.global_position, Color8(0x66, 0xcc, 0xff), 30)
	trigger_flash(Color8(0x99, 0xdd, 0xff), 0.45)
	main.hitstop_t = 0.09


# 닌자 — 표창 난사: 부채꼴 표창 7개
func _cast_shuriken_storm() -> void:
	var pl: Node2D = main.player
	var base_ang := 0.0 if pl.face >= 0 else PI
	var spd := 360.0
	for i in range(-3, 4):
		var ang := base_ang + i * 0.18
		fireballs.append({
			"pos": pl.global_position, "vel": Vector2(cos(ang) * spd, sin(ang) * spd),
			"t": 0.0, "life": 1.6, "exploded": false, "exp_t": 0.0, "kind": "shuriken",
		})
	main.fx.add_particles(pl.global_position, Color8(0x88, 0xff, 0xcc), 14)
	trigger_flash(Color8(0x88, 0xff, 0xcc), 0.22)


# 닌자 — 그림자 질주: 전방 길게 순간이동 + 경로 적 베기
func _cast_shadow_dash() -> void:
	var pl: Node2D = main.player
	var p: Dictionary = GameState.player
	var dist := 280.0
	var sx := pl.global_position.x
	var sy := pl.global_position.y
	var nx := clampf(pl.global_position.x + pl.face * dist, 40.0, GameData.WORLD_W - 40.0)
	var dmg := roundf(float(p["atkPow"]) * 1.6 * skill_dmg_mult())
	for e in main.enemies:
		if not is_instance_valid(e) or e.dead or e.hp <= 0.0:
			continue
		var ep: Vector2 = e.global_position
		var ex := ep.x
		var between := (ex - minf(sx, nx) > -60.0) and (maxf(sx, nx) - ex > -60.0)
		if between and absf(ep.y - sy) < 90.0:
			_hit_enemy(e, dmg, false, Color8(0x44, 0xdd, 0xaa), 5)
	for i in 6:
		var gx := sx + (nx - sx) * (float(i) / 5.0)
		main.fx.add_particles(Vector2(gx, sy), Color8(0x44, 0xdd, 0xaa), 4)
	pl.global_position.x = nx
	p["x"] = nx
	p["inv"] = 0.4
	main.spawn_impact(Vector2(nx, sy), 80.0, Color8(0x88, 0xff, 0xcc))
	trigger_flash(Color8(0x44, 0xdd, 0xaa), 0.25)


# 마법사 — 빙결 폭발
func _cast_frost_nova() -> void:
	var pl: Node2D = main.player
	var p: Dictionary = GameState.player
	var dmg := roundf(float(p["atkPow"]) * 1.8 * skill_dmg_mult())
	for e in main.enemies:
		if not is_instance_valid(e) or e.dead or e.hp <= 0.0:
			continue
		if pl.global_position.distance_to(e.global_position) < 175.0:
			_hit_enemy(e, dmg, false, Color8(0x88, 0xdd, 0xff), 6)
	main.spawn_impact(pl.global_position, 175.0, Color8(0x66, 0xcc, 0xff))
	trigger_flash(Color8(0x66, 0xcc, 0xff), 0.18)


# 마법사 — 번개 사슬: 가까운 적 최대 5마리
func _cast_chain_bolt() -> void:
	var pl: Node2D = main.player
	var p: Dictionary = GameState.player
	var dmg := roundf(float(p["atkPow"]) * 1.6 * skill_dmg_mult())
	var cands: Array = []
	for e in main.enemies:
		if not is_instance_valid(e) or e.dead or e.hp <= 0.0:
			continue
		var ep: Vector2 = e.global_position
		var d := pl.global_position.distance_to(ep)
		if d < 320.0:
			cands.append({"e": e, "d": d})
	cands.sort_custom(func(a, b): return a["d"] < b["d"])
	var prev := pl.global_position
	for i in min(5, cands.size()):
		var e = cands[i]["e"]
		_hit_enemy(e, dmg, false, Color8(0x88, 0xdd, 0xff), 5)
		for j in range(1, 5):
			main.fx.add_particles(prev.lerp(e.global_position, float(j) / 4.0), Color8(0xaa, 0xee, 0xff), 1)
		prev = e.global_position
	trigger_flash(Color8(0x88, 0xdd, 0xff), 0.15)


# 마법사 — 화염 기둥: 전방 지점 불기둥
func _cast_flame_pillar() -> void:
	var pl: Node2D = main.player
	var p: Dictionary = GameState.player
	var dmg := roundf(float(p["atkPow"]) * 2.4 * skill_dmg_mult())
	var c := Vector2(pl.global_position.x + pl.face * 150.0, pl.global_position.y)
	for e in main.enemies:
		if not is_instance_valid(e) or e.dead or e.hp <= 0.0:
			continue
		if c.distance_to(e.global_position) < 110.0:
			_hit_enemy(e, dmg, false, Color8(0xff, 0x77, 0x33), 7)
	main.spawn_impact(c, 110.0, Color8(0xff, 0x77, 0x33))
	main.fx.add_particles(c, Color8(0xff, 0xcc, 0x44), 12)
	trigger_flash(Color8(0xff, 0x77, 0x33), 0.18)


# 검사 — 분쇄 강타: 전방 부채꼴 + 넉백
func _cast_crush_blow() -> void:
	var pl: Node2D = main.player
	var p: Dictionary = GameState.player
	var dmg := roundf(float(p["atkPow"]) * 2.6 * skill_dmg_mult())
	var face: int = pl.face
	var c := Vector2(pl.global_position.x + face * 80.0, pl.global_position.y)
	for e in main.enemies:
		if not is_instance_valid(e) or e.dead or e.hp <= 0.0:
			continue
		var ep: Vector2 = e.global_position
		if Vector2(c.x - ep.x, pl.global_position.y - ep.y).length() < 130.0 \
				and (ep.x - pl.global_position.x) * face > -30.0:
			var a := (ep - pl.global_position).angle()
			e.global_position = ep + Vector2(cos(a), sin(a)) * 40.0
			_hit_enemy(e, dmg, true, Color8(0xff, 0xcc, 0x44), 6)
	main.spawn_impact(c, 130.0, Color8(0xff, 0xcc, 0x44))
	trigger_flash(Color8(0xff, 0xcc, 0x44), 0.18)


# 검사 — 대지 가르기: 전방 직선상 적
func _cast_earth_split() -> void:
	var pl: Node2D = main.player
	var p: Dictionary = GameState.player
	var dmg := roundf(float(p["atkPow"]) * 2.2 * skill_dmg_mult())
	var face: int = pl.face
	var reach := 300.0
	for e in main.enemies:
		if not is_instance_valid(e) or e.dead or e.hp <= 0.0:
			continue
		var ep: Vector2 = e.global_position
		var dx := (ep.x - pl.global_position.x) * face
		if dx > 0.0 and dx < reach and absf(ep.y - pl.global_position.y) < 60.0:
			_hit_enemy(e, dmg, false, Color8(0xdd, 0x88, 0x44), 6)
	for i in range(1, 9):
		main.fx.add_particles(Vector2(pl.global_position.x + face * reach * i / 8.0, pl.global_position.y), Color8(0xdd, 0x88, 0x44), 2)
	trigger_flash(Color8(0xdd, 0x88, 0x44), 0.15)


# 도적 — 독칼 난무: 전방 부채꼴
func _cast_poison_fan() -> void:
	var pl: Node2D = main.player
	var p: Dictionary = GameState.player
	var dmg := roundf(float(p["atkPow"]) * 1.5 * skill_dmg_mult())
	var face: int = pl.face
	for e in main.enemies:
		if not is_instance_valid(e) or e.dead or e.hp <= 0.0:
			continue
		var ep: Vector2 = e.global_position
		var dx := (ep.x - pl.global_position.x) * face
		if dx > -20.0 and pl.global_position.distance_to(ep) < 200.0:
			_hit_enemy(e, dmg, false, Color8(0x88, 0xdd, 0x66), 5)
	for i in range(-2, 3):
		main.fx.add_particles(Vector2(pl.global_position.x + face * 120.0, pl.global_position.y + i * 30.0), Color8(0x88, 0xdd, 0x66), 2)
	trigger_flash(Color8(0x88, 0xdd, 0x66), 0.12)


# 도적 — 그림자 일격: 가장 가까운 적에 순간이동 + 치명타
func _cast_shadow_strike() -> void:
	var pl: Node2D = main.player
	var p: Dictionary = GameState.player
	var dmg := roundf(float(p["atkPow"]) * 3.0 * skill_dmg_mult())
	var t = _nearest_enemy()
	if t != null:
		var nx := clampf(t.global_position.x - pl.face * 50.0, 40.0, GameData.WORLD_W - 40.0)
		main.fx.add_particles(pl.global_position, Color8(0x99, 0x66, 0xdd), 5)
		pl.global_position.x = nx
		p["x"] = nx
		p["inv"] = 0.4
		_hit_enemy(t, dmg, true, Color8(0x99, 0x66, 0xdd), 8)
		main.spawn_impact(t.global_position, 70.0, Color8(0x99, 0x66, 0xdd))
	trigger_flash(Color8(0x99, 0x66, 0xdd), 0.18)


# ════════════════════════════════════════════════════════════
#  공용 헬퍼
# ════════════════════════════════════════════════════════════
# 적 1마리에 데미지 + 플래시 + 데미지숫자 + 파티클 (mino1 반복 블록 공통화)
func _hit_enemy(e: Node, dmg: float, is_crit: bool, part_color: Color, part_n: int) -> void:
	e.hp -= dmg
	e.flash_t = 0.2
	if is_instance_valid(e) and e.has_node("Sprite"):
		e.get_node("Sprite").modulate = Color.WHITE
	main.spawn_float_text(e.global_position, str(int(dmg)), is_crit)
	if part_n > 0:
		main.fx.add_particles(e.global_position, part_color, part_n)


# 범위 데미지 (mino1 _aoeDamage) — 중심 반경 내 모든 적
func _aoe_damage(center: Vector2, r: float, dmg: float, part_color: Color) -> int:
	var hit := 0
	for e in main.enemies:
		if not is_instance_valid(e) or e.dead or e.hp <= 0.0:
			continue
		if center.distance_to(e.global_position) <= r:
			_hit_enemy(e, dmg, false, part_color, 6)
			hit += 1
	return hit


func _nearest_enemy() -> Node:
	var best: Node = null
	var bd := 1.0e9
	var pl: Node2D = main.player
	for e in main.enemies:
		if not is_instance_valid(e) or e.dead or e.hp <= 0.0:
			continue
		var ep: Vector2 = e.global_position
		var d := pl.global_position.distance_to(ep)
		if d < bd:
			bd = d
			best = e
	return best


# 화면 전체 색 플래시 (mino1 _triggerFlash)
func trigger_flash(color: Color, strength: float) -> void:
	flash_color = color
	flash_max = 0.22
	flash_t = 0.22
	flash_strength = strength


# 현재 플래시 알파 (Main 의 플래시 오버레이가 매 프레임 읽음)
func flash_alpha() -> float:
	if flash_t <= 0.0:
		return 0.0
	return maxf(0.0, flash_t / flash_max) * flash_strength


# 스킬 피드백 텍스트 (mino1 _showSkillFeedback) — 화면 우하단
func _feedback(msg: String, color: Color) -> void:
	if main and main.has_method("show_skill_feedback"):
		main.show_skill_feedback(msg, color)


# ════════════════════════════════════════════════════════════
#  소환 슬라임 (mino1 _spawnAllySlime / _updateAllySlimes)
# ════════════════════════════════════════════════════════════
func _spawn_ally_slime(wx: float, wy: float) -> void:
	var node := Sprite2D.new()
	var tex = main._load_ally_tex() if main.has_method("_load_ally_tex") else null
	if tex:
		node.texture = tex
		var h := float(tex.get_height())
		var s := 56.0 / h if h > 0.0 else 1.0
		node.scale = Vector2(s, s * 0.92)
	else:
		var ph := Image.create(40, 40, false, Image.FORMAT_RGBA8)
		ph.fill(Color8(0x66, 0xaa, 0xff))
		node.texture = ImageTexture.create_from_image(ph)
	node.modulate = Color8(0x66, 0xaa, 0xff)
	node.global_position = Vector2(wx, wy)
	node.z_index = int(wy)
	add_child(node)
	ally_slimes.append({"node": node, "atk_timer": 0.0, "anim_t": 0.0, "base_scale": node.scale})


func _update_ally_slimes(dt: float) -> void:
	var pl: Node2D = main.player
	for i in range(ally_slimes.size() - 1, -1, -1):
		var ally: Dictionary = ally_slimes[i]
		var s: Sprite2D = ally["node"]
		if not is_instance_valid(s):
			ally_slimes.remove_at(i)
			continue
		# 주인공 뒤를 따라옴
		var follow_dist := 50.0 + i * 20.0
		var d := pl.global_position - s.global_position
		var dist := d.length()
		if dist < 1.0:
			dist = 1.0
		if dist > follow_dist + 10.0:
			var spd := 160.0 if dist > 180.0 else 90.0
			var tx := pl.global_position.x - (d.x / dist) * follow_dist
			var ty := pl.global_position.y - (d.y / dist) * follow_dist
			var lerp_amt := minf(1.0, spd * dt / maxf(dist, 1.0))
			s.global_position.x += (tx - s.global_position.x) * lerp_amt
			s.global_position.y += (ty - s.global_position.y) * lerp_amt
		s.flip_h = d.x > 0.0
		s.z_index = int(s.global_position.y)

		# 1초마다 사거리(90) 내 가장 가까운 적 자동 공격
		ally["atk_timer"] = float(ally["atk_timer"]) + dt
		if float(ally["atk_timer"]) >= 1.0:
			ally["atk_timer"] = 0.0
			var nearest: Node = null
			var near_dist := 90.0
			for e in main.enemies:
				if not is_instance_valid(e) or e.dead or e.hp <= 0.0:
					continue
				var ed := s.global_position.distance_to(e.global_position)
				if ed < near_dist:
					near_dist = ed
					nearest = e
			if nearest != null:
				_hit_enemy(nearest, ALLY_SLIME_BASE_ATK, false, Color8(0x66, 0xaa, 0xff), 0)

		# 점프 애니 (squash&stretch)
		ally["anim_t"] = float(ally["anim_t"]) + dt
		var bs: Vector2 = ally["base_scale"]
		var moving := dist > follow_dist + 12.0
		var at: float = ally["anim_t"]
		if moving:
			var phase := sin(at * 10.0)
			var sq_y := 1.0 + (-0.20 * phase if phase > 0.0 else 0.15 * absf(phase))
			var sq_x := 2.0 - sq_y
			s.scale = Vector2(bs.x * sq_x, bs.y * sq_y)
		else:
			var breathe := 1.0 + sin(at * 2.0) * 0.05
			s.scale = Vector2(bs.x * breathe, bs.y / breathe)


# ════════════════════════════════════════════════════════════
#  발사체·메테오·장판 갱신 (mino1 _updateSkills 의 나머지)
# ════════════════════════════════════════════════════════════
const MAX_FIREBALLS := 8

func _update_fireballs(dt: float) -> void:
	var p: Dictionary = GameState.player
	for i in range(fireballs.size() - 1, -1, -1):
		var fb: Dictionary = fireballs[i]
		if fb["exploded"]:
			fb["exp_t"] = float(fb["exp_t"]) + dt
			if float(fb["exp_t"]) / 0.4 >= 1.0:
				fireballs.remove_at(i)
			continue
		fb["t"] = float(fb["t"]) + dt
		fb["pos"] = (fb["pos"] as Vector2) + (fb["vel"] as Vector2) * dt
		var pos: Vector2 = fb["pos"]
		# 적 명중 판정
		var hit := false
		for e in main.enemies:
			if not is_instance_valid(e) or e.dead or e.hp <= 0.0:
				continue
			if pos.distance_to(e.global_position) < 38.0:
				# 폭발 범위 데미지 (반경 55)
				for e2 in main.enemies:
					if not is_instance_valid(e2) or e2.dead or e2.hp <= 0.0:
						continue
					if pos.distance_to(e2.global_position) < 55.0:
						var dmg := roundf(float(p["atkPow"]) * 1.8 * skill_dmg_mult())
						_hit_enemy(e2, dmg, false, Color8(0xff, 0x88, 0x22), 0)
				fb["exploded"] = true
				fb["exp_t"] = 0.0
				main.fx.add_particles(pos, Color8(0xff, 0x66, 0x22), 14)
				hit = true
				break
		if hit:
			continue
		if float(fb["t"]) >= float(fb["life"]) or pos.x < 0.0 or pos.x > GameData.WORLD_W or pos.y < 0.0 or pos.y > GameData.WORLD_H:
			fireballs.remove_at(i)
	if fireballs.size() > MAX_FIREBALLS:
		fireballs = fireballs.slice(fireballs.size() - MAX_FIREBALLS)


func _update_meteors(dt: float) -> void:
	var p: Dictionary = GameState.player
	for i in range(skill_meteors.size() - 1, -1, -1):
		var m: Dictionary = skill_meteors[i]
		if m["hit"]:
			m["hit_t"] = float(m["hit_t"]) + dt
			if float(m["hit_t"]) >= 0.5:
				skill_meteors.remove_at(i)
			continue
		if float(m["warn_t"]) > 0.0:
			m["warn_t"] = float(m["warn_t"]) - dt
			if float(m["warn_t"]) <= 0.0:
				m["falling"] = true
			continue
		if m["falling"]:
			m["fall_y"] = float(m["fall_y"]) + 980.0 * dt
			if float(m["fall_y"]) >= float(m["ty"]):
				m["fall_y"] = m["ty"]
				m["hit"] = true
				m["hit_t"] = 0.0
				# 범위 데미지 (반경 65)
				var center := Vector2(m["tx"], m["ty"])
				for e in main.enemies:
					if not is_instance_valid(e) or e.dead or e.hp <= 0.0:
						continue
					if center.distance_to(e.global_position) < 65.0:
						var dmg := roundf(float(p["atkPow"]) * 2.5 * skill_dmg_mult())
						_hit_enemy(e, dmg, false, Color8(0xff, 0x88, 0x22), 8)
				main.fx.add_particles(center, Color8(0xff, 0x66, 0x22), 20)
				main.add_shake(0.12, 5.0)


func _update_waterfalls(dt: float) -> void:
	var p: Dictionary = GameState.player
	for i in range(waterfalls.size() - 1, -1, -1):
		var wf: Dictionary = waterfalls[i]
		wf["t"] = float(wf["t"]) + dt
		if float(wf["t"]) >= float(wf["life"]):
			waterfalls.remove_at(i)
			continue
		wf["tick_t"] = float(wf["tick_t"]) + dt
		if float(wf["tick_t"]) >= 1.0:
			wf["tick_t"] = float(wf["tick_t"]) - 1.0
			var dmg := roundf(float(p["atkPow"]) * 0.7 * float(wf["dmg_mult"]))
			var wpos: Vector2 = wf["pos"]
			var hw := float(wf["w"]) / 2.0 + 10.0
			var hh := float(wf["h"]) / 2.0 + 10.0
			for e in main.enemies:
				if not is_instance_valid(e) or e.dead or e.hp <= 0.0:
					continue
				if absf(e.global_position.x - wpos.x) < hw and absf(e.global_position.y - wpos.y) < hh:
					_hit_enemy(e, dmg, false, Color8(0x44, 0xaa, 0xff), 0)
			main.fx.add_particles(wpos, Color8(0x44, 0xaa, 0xff), 6)


# ════════════════════════════════════════════════════════════
#  월드 좌표 직접 그리기 (투사체·메테오·장판) — Node2D _draw
# ════════════════════════════════════════════════════════════
func _draw() -> void:
	# ── 파이어볼/표창 ──
	for fb in fireballs:
		var pos: Vector2 = fb["pos"]
		if fb["exploded"]:
			var pct := float(fb["exp_t"]) / 0.4
			if pct < 1.0:
				var r := 48.0 * (1.0 - pct * 0.4)
				var a := (1.0 - pct) * 0.85
				draw_circle(pos, r, Color(1.0, 0.4, 0.13, a))
				draw_circle(pos, r * 0.5, Color(1.0, 0.8, 0.27, a * 0.6))
			continue
		if fb.get("kind", "fireball") == "shuriken":
			# 표창: 회전하는 작은 별 (청록)
			var ang := float(fb["t"]) * 22.0
			var pts := PackedVector2Array()
			for k in 4:
				var aa := ang + k * (PI / 2.0)
				pts.append(pos + Vector2(cos(aa), sin(aa)) * 10.0)
			draw_colored_polygon(pts, Color(0.53, 1.0, 0.8, 0.95))
			draw_circle(pos, 4.0, Color(1, 1, 1, 0.8))
		else:
			var flicker := 0.7 + 0.3 * sin(float(fb["t"]) * 18.0)
			draw_circle(pos, 12.0, Color(1.0, 0.27, 0.0, flicker))
			var vel: Vector2 = fb["vel"]
			draw_circle(pos - vel * 0.025, 7.0, Color(1.0, 0.67, 0.13, flicker * 0.8))
			draw_circle(pos, 4.0, Color(1, 1, 1, flicker * 0.4))

	# ── 메테오 (경고원 → 낙하 → 폭발) ──
	for m in skill_meteors:
		var c := Vector2(m["tx"], m["ty"])
		if m["hit"]:
			var pct2 := float(m["hit_t"]) / 0.5
			if pct2 < 1.0:
				draw_circle(c, 75.0 * (1.0 - pct2), Color(1.0, 0.4, 0.13, (1.0 - pct2) * 0.85))
			continue
		if float(m["warn_t"]) > 0.0:
			var pulse := 0.5 + 0.5 * sin(float(m["warn_t"]) * 12.0)
			draw_arc(c, 56.0, 0.0, TAU, 36, Color(1.0, 0.4, 0.13, 0.9 * pulse), 3.0)
			draw_circle(c, 56.0, Color(1.0, 0.27, 0.0, 0.14 * pulse))
			continue
		if m["falling"]:
			var fp := Vector2(m["tx"], m["fall_y"])
			draw_rect(Rect2(fp.x - 9.0, fp.y - 58.0, 18.0, 58.0), Color(1.0, 0.67, 0.16, 0.65))
			draw_circle(fp, 14.0, Color(0.35, 0.27, 0.21))
			draw_circle(fp, 9.0, Color(1.0, 0.87, 0.53))

	# ── 워터폴 장판 ──
	for wf in waterfalls:
		var wp: Vector2 = wf["pos"]
		var ww: float = wf["w"]
		var wh: float = wf["h"]
		var pct3 := float(wf["t"]) / float(wf["life"])
		var alpha := 0.7 * (1.0 - pct3 * 0.4)
		draw_rect(Rect2(wp.x - ww / 2.0, wp.y - wh / 2.0, ww, wh), Color(0.07, 0.4, 0.8, alpha * 0.55))
		draw_rect(Rect2(wp.x - ww * 0.25, wp.y - wh / 2.0 + 4.0, ww * 0.5, wh - 8.0), Color(0.27, 0.67, 1.0, alpha * 0.4))
		var wave_off := sin(float(wf["t"]) * 8.0) * 4.0
		draw_rect(Rect2(wp.x - ww / 2.0 + wave_off, wp.y - wh / 2.0, ww - wave_off * 2.0, wh), Color(0.53, 0.87, 1.0, alpha * 0.85), false, 2.5)
