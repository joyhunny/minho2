extends Node
## GameData — mino1 core.js 의 모든 데이터·공식을 그대로 옮긴 단일 정본(autoload 싱글톤).
## 밸런스 숫자(적 HP·dmg·xp·난이도 배율·드랍률 등)는 mino1 값을 절대 보존한다.
## core.js 의 window.MinoCore.* 를 Godot 에서 GameData.* 로 쓴다.

# ── 월드 크기 (core.js: WORLD) ──────────────────────────────
const WORLD := Vector2(2200, 2200)
const WORLD_W := 2200.0
const WORLD_H := 2200.0

# ── 적 타입 데이터 (core.js: ENEMY_DEFS, 9종) ────────────────
# 각 항목: name(이름) hp sp(속도) dmg xp sprite(이미지키) min_lvl(등장레벨)
const ENEMY_DEFS := {
	"slime":    {"name": "슬라임",        "hp": 39,  "sp": 80,  "dmg": 5,  "xp": 10, "sprite": "slime",    "min_lvl": 1},
	"rat":      {"name": "변이 쥐",       "hp": 18,  "sp": 140, "dmg": 4,  "xp": 6,  "sprite": "rat",      "min_lvl": 1},
	"pig":      {"name": "못난 돼지",     "hp": 55,  "sp": 70,  "dmg": 7,  "xp": 13, "sprite": "pig",      "min_lvl": 2},
	"crow":     {"name": "오염 까마귀",   "hp": 23,  "sp": 110, "dmg": 6,  "xp": 9,  "sprite": "crow",     "min_lvl": 2},
	"toad":     {"name": "독두꺼비",      "hp": 36,  "sp": 65,  "dmg": 9,  "xp": 14, "sprite": "toad",     "min_lvl": 3},
	"hedgehog": {"name": "가시 고슴도치", "hp": 47,  "sp": 78,  "dmg": 10, "xp": 16, "sprite": "hedgehog", "min_lvl": 3},
	"boar":     {"name": "녹슨 멧돼지",   "hp": 83,  "sp": 95,  "dmg": 12, "xp": 21, "sprite": "boar",     "min_lvl": 4},
	"croc":     {"name": "늪 악어",       "hp": 101, "sp": 58,  "dmg": 15, "xp": 26, "sprite": "croc",     "min_lvl": 5},
	"wolf":     {"name": "변종 늑대",     "hp": 75,  "sp": 125, "dmg": 13, "xp": 23, "sprite": "wolf",     "min_lvl": 6},
}

# ── 지역 정의 (core.js: REGION_DEFS, 4지역) ──────────────────
# 색은 core.js 의 0xRRGGBB 를 Godot Color 로 변환.
const REGION_DEFS := [
	{
		"id": "field", "name": "오염된 들판", "icon": "🌿",
		"desc": "오염이 막 번진 풀밭. 약한 변이체들이 나온다.",
		"ground_tint": Color8(0xff, 0xff, 0xff), "panel_color": Color8(0x9f, 0xe3, 0xa8),
		"enemies": ["slime", "rat", "pig", "crow"],
		"boss": "boar_king",
		"rocks": 8, "poison": 3, "buffs": 2, "move_mult": 1.0,
		"rock_color": Color8(0x4a, 0x50, 0x40), "elite_rate": 0.06,
	},
	{
		"id": "swamp", "name": "독 늪지", "icon": "🟢",
		"desc": "독이 고인 끈적한 늪. 발이 느려지고 독웅덩이가 우글거린다.",
		"ground_tint": Color8(0x7e, 0xc8, 0xb0), "panel_color": Color8(0x44, 0xdd, 0x88),
		"enemies": ["toad", "hedgehog", "croc", "slime"],
		"boss": "croc",
		"rocks": 6, "poison": 16, "buffs": 1, "move_mult": 0.72,
		"rock_color": Color8(0x3f, 0x58, 0x36), "elite_rate": 0.08,
	},
	{
		"id": "ruins", "name": "무너진 폐허", "icon": "🏚️",
		"desc": "부서진 도시의 잔해. 좁은 길마다 사나운 짐승들이 도사린다.",
		"ground_tint": Color8(0xca, 0xbf, 0xa0), "panel_color": Color8(0xd8, 0xc0, 0x70),
		"enemies": ["boar", "wolf", "crow", "hedgehog"],
		"boss": "wolf_king",
		"rocks": 20, "poison": 4, "buffs": 2, "move_mult": 1.0,
		"rock_color": Color8(0x6a, 0x62, 0x58), "elite_rate": 0.10,
	},
	{
		"id": "castle", "name": "군주의 성", "icon": "🏰",
		"desc": "오염의 군주가 도사린 마지막 땅. 정예가 빽빽하다.",
		"ground_tint": Color8(0xc0, 0x90, 0xc0), "panel_color": Color8(0xff, 0x88, 0x66),
		"enemies": ["wolf", "croc", "boar", "toad"],
		"boss": "elephant",
		"rocks": 12, "poison": 8, "buffs": 2, "move_mult": 0.9,
		"rock_color": Color8(0x4a, 0x3a, 0x5a), "elite_rate": 0.14,
	},
]

# ── 레벨업 스킬 정의 (core.js: SKILL_DEFS, 8종) ──────────────
const SKILL_DEFS := {
	"sword_mastery": {"name": "검술 수련", "icon": "⚔️", "desc": "근접 데미지 +5",          "max_stack": 5, "min_lvl": 1},
	"quick_strike":  {"name": "공격 가속", "icon": "💨", "desc": "공격 쿨다운 20% 감소",     "max_stack": 4, "min_lvl": 2},
	"iron_wall":     {"name": "철벽",      "icon": "🛡️", "desc": "받는 피해 -3",             "max_stack": 5, "min_lvl": 1},
	"swift_wind":    {"name": "질풍",      "icon": "🌀", "desc": "이동속도 +22",            "max_stack": 4, "min_lvl": 1},
	"wide_slash":    {"name": "범위 확대", "icon": "🌊", "desc": "공격 범위 +14",           "max_stack": 4, "min_lvl": 1},
	"vitality":      {"name": "체력 강화", "icon": "❤️", "desc": "최대 체력 +20, 즉시 회복", "max_stack": 5, "min_lvl": 1},
	"critical":      {"name": "치명타",    "icon": "💥", "desc": "확률로 2배 피해",          "max_stack": 4, "min_lvl": 2},
	"life_drain":    {"name": "생명 흡수", "icon": "🩸", "desc": "근접 명중 시 체력 소량 회복", "max_stack": 4, "min_lvl": 2},
}

# ── 장비 희귀도 테이블 (core.js: RARITY_TABLE, 5등급) ────────
const RARITY_TABLE := [
	{"name": "일반", "color": Color("#aaaaaa"), "border": Color("#888888"), "chance": 0.25},
	{"name": "고급", "color": Color("#4caf50"), "border": Color("#2e7d32"), "chance": 0.10},
	{"name": "희귀", "color": Color("#2196f3"), "border": Color("#0d47a1"), "chance": 0.04},
	{"name": "에픽", "color": Color("#b15be0"), "border": Color("#6a1b9a"), "chance": 0.018},
	{"name": "전설", "color": Color("#ff9800"), "border": Color("#e65100"), "chance": 0.008},
]

# ── 장비 정의 (core.js: ITEM_DEFS) ──────────────────────────
# slot: weapon/armor/accessory, rarity: 0~4, no_drop: 전직 전용(드랍 제외)
const ITEM_DEFS := {
	# 무기
	"rusty_knife":          {"slot": "weapon",    "rarity": 0, "name": "녹슨 칼",         "stats": {"atkPow": 4}},
	"iron_sword":           {"slot": "weapon",    "rarity": 0, "name": "쇳덩이 검",        "stats": {"atkPow": 8, "atkRange": 6}},
	"sharp_dagger":         {"slot": "weapon",    "rarity": 1, "name": "예리한 단검",      "stats": {"atkPow": 6, "atkSpeed": -0.05}},
	"forest_axe":           {"slot": "weapon",    "rarity": 1, "name": "벌목 도끼",        "stats": {"atkPow": 14, "atkSpeed": 0.08}},
	"slime_club":           {"slot": "weapon",    "rarity": 1, "name": "슬라임 뭉치",      "stats": {"atkPow": 10, "atkRange": 12}},
	"copper_spear":         {"slot": "weapon",    "rarity": 1, "name": "구리 창",          "stats": {"atkPow": 9, "atkSpeed": -0.03, "atkRange": 20}},
	"hunters_bow":          {"slot": "weapon",    "rarity": 2, "name": "사냥꾼 활",        "stats": {"atkPow": 16, "atkSpeed": -0.06, "atkRange": 28}},
	"capy_tusk":            {"slot": "weapon",    "rarity": 2, "name": "카피바라 이빨",    "stats": {"atkPow": 20, "atkRange": 8}},
	"swamp_fang":           {"slot": "weapon",    "rarity": 2, "name": "늪 독니",          "stats": {"atkPow": 18, "atkSpeed": -0.05}},
	"cursed_blade":         {"slot": "weapon",    "rarity": 4, "name": "저주받은 칼날",    "stats": {"atkPow": 28, "atkSpeed": -0.08, "atkRange": 10}},
	"thunder_staff":        {"slot": "weapon",    "rarity": 4, "name": "번개 지팡이",      "stats": {"atkPow": 22, "atkSpeed": -0.10, "atkRange": 30}},
	"contamination_scythe": {"slot": "weapon",    "rarity": 4, "name": "오염 낫",          "stats": {"atkPow": 32, "atkRange": 18}},
	# 에픽(보라) 무기
	"venom_glaive":         {"slot": "weapon",    "rarity": 3, "name": "맹독 글레이브",    "stats": {"atkPow": 24, "atkRange": 14, "atkSpeed": -0.04}},
	"frost_edge":           {"slot": "weapon",    "rarity": 3, "name": "서리 칼날",        "stats": {"atkPow": 23, "atkSpeed": -0.07}},
	"ruin_hammer":          {"slot": "weapon",    "rarity": 3, "name": "폐허의 망치",      "stats": {"atkPow": 26, "atkRange": 10}},
	# 전직 전용 무기 (no_drop) — 1차 전직 기본 지급
	"mage_staff":           {"slot": "weapon",    "rarity": 2, "name": "마법사 스태프",    "stats": {"atkPow": 12, "atkRange": 30, "maxmp": 30}, "no_drop": true},
	"great_sword":          {"slot": "weapon",    "rarity": 2, "name": "대검",             "stats": {"atkPow": 22, "atkRange": 14},          "no_drop": true},
	"combat_dagger":        {"slot": "weapon",    "rarity": 2, "name": "단검",             "stats": {"atkPow": 12, "atkSpeed": -0.08},        "no_drop": true},
	# 2차 전직 기본 지급 (강력)
	"harry_wand":           {"slot": "weapon",    "rarity": 4, "name": "마법 지팡이",      "stats": {"atkPow": 28, "atkRange": 40, "maxmp": 60}, "no_drop": true},
	"twin_blades":          {"slot": "weapon",    "rarity": 4, "name": "쌍검",             "stats": {"atkPow": 30, "atkRange": 14, "atkSpeed": -0.10}, "no_drop": true},
	"ninja_shuriken":       {"slot": "weapon",    "rarity": 4, "name": "표창",             "stats": {"atkPow": 26, "atkRange": 34, "atkSpeed": -0.12}, "no_drop": true},
	# 방어구
	"tattered_cloth":       {"slot": "armor",     "rarity": 0, "name": "너덜너덜 천",      "stats": {"armor": 1, "maxhp": 10}},
	"leather_vest":         {"slot": "armor",     "rarity": 0, "name": "가죽 조끼",        "stats": {"armor": 3, "maxhp": 15}},
	"pig_hide":             {"slot": "armor",     "rarity": 0, "name": "돼지 가죽",        "stats": {"armor": 4, "maxhp": 20}},
	"slime_coat":           {"slot": "armor",     "rarity": 1, "name": "슬라임 코팅",      "stats": {"armor": 5, "maxhp": 25}},
	"iron_plate":           {"slot": "armor",     "rarity": 1, "name": "철판 조각",        "stats": {"armor": 8, "maxhp": 18}},
	"capy_fur":             {"slot": "armor",     "rarity": 1, "name": "카피바라 털가죽",  "stats": {"armor": 6, "maxhp": 35}},
	"boar_armor":           {"slot": "armor",     "rarity": 2, "name": "멧돼지 강판",      "stats": {"armor": 12, "maxhp": 30}},
	"scale_mail":           {"slot": "armor",     "rarity": 2, "name": "비늘 갑옷",        "stats": {"armor": 10, "maxhp": 50}},
	"crow_feather_cloak":   {"slot": "armor",     "rarity": 2, "name": "까마귀 깃털 망토", "stats": {"armor": 7, "maxhp": 40}},
	"wolf_pelt":            {"slot": "armor",     "rarity": 4, "name": "늑대 가죽",        "stats": {"armor": 15, "maxhp": 55}},
	"slime_queen_shell":    {"slot": "armor",     "rarity": 4, "name": "슬라임 여왕 껍데기", "stats": {"armor": 13, "maxhp": 80}},
	"elephant_skin":        {"slot": "armor",     "rarity": 4, "name": "코끼리 변이 피부", "stats": {"armor": 20, "maxhp": 60}},
	# 에픽(보라) 방어구
	"amethyst_plate":       {"slot": "armor",     "rarity": 3, "name": "자수정 갑옷",      "stats": {"armor": 13, "maxhp": 48}},
	"shadow_mantle":        {"slot": "armor",     "rarity": 3, "name": "그림자 망토",      "stats": {"armor": 11, "maxhp": 62}},
	# 악세서리
	"worn_boots":           {"slot": "accessory", "rarity": 0, "name": "닳은 운동화",      "stats": {"sp": 18}},
	"rat_tail":             {"slot": "accessory", "rarity": 0, "name": "쥐 꼬리 부적",     "stats": {"sp": 10}},
	"slime_pendant":        {"slot": "accessory", "rarity": 1, "name": "슬라임 목걸이",    "stats": {"maxhp": 15}},
	"capy_claw":            {"slot": "accessory", "rarity": 1, "name": "카피바라 발톱",    "stats": {"sp": 28}},
	"toad_venom_ring":      {"slot": "accessory", "rarity": 1, "name": "독두꺼비 독반지",  "stats": {"armor": 2}},
	"boar_tusk_ring":       {"slot": "accessory", "rarity": 2, "name": "멧돼지 어금니 반지", "stats": {"sp": 20}},
	"crow_eye_lens":        {"slot": "accessory", "rarity": 2, "name": "까마귀 눈 렌즈",   "stats": {"sp": 15}},
	"wolf_fang_chain":      {"slot": "accessory", "rarity": 2, "name": "늑대 이빨 사슬",   "stats": {"sp": 35}},
	"capy_heart":           {"slot": "accessory", "rarity": 4, "name": "카피바라 심장",    "stats": {"maxhp": 40}},
	"slime_core":           {"slot": "accessory", "rarity": 4, "name": "슬라임 핵",        "stats": {"sp": 25, "maxhp": 20}},
	"pollution_crown":      {"slot": "accessory", "rarity": 4, "name": "오염 왕관",        "stats": {"sp": 20, "atkPow": 8}},
	# 에픽(보라) 악세서리
	"amethyst_ring":        {"slot": "accessory", "rarity": 3, "name": "자수정 반지",      "stats": {"atkPow": 6, "maxhp": 28}},
	"void_charm":           {"slot": "accessory", "rarity": 3, "name": "공허의 부적",      "stats": {"sp": 30, "armor": 3}},
}

# ── 골드 판매 가격표 (core.js: GOLD_SELL_PRICE, 희귀도별) ────
const GOLD_SELL_PRICE := [15, 40, 90, 170, 340]

# ── 골드 드랍량 (core.js: GOLD_DROP, 적 종류별 기본) ─────────
const GOLD_DROP := {
	"slime": 3, "rat": 2, "pig": 5, "crow": 4, "toad": 6, "hedgehog": 5,
	"boar": 8, "croc": 10, "wolf": 9,
}

# ── 난이도 (core.js: DIFFICULTY_DEFS, 10단계) ───────────────
# dmg_mult=적 피해 배율, hp_mult=적 체력 배율, regen=초당 자동 회복
const DIFFICULTY_DEFS := [
	{"id": "easy",       "name": "쉬움",       "sub": "느긋하게 즐기기", "dmg_mult": 0.5,  "hp_mult": 0.8,  "regen": 3, "color": Color("#4caf50")},
	{"id": "normal",     "name": "보통",       "sub": "기본 밸런스",     "dmg_mult": 1.0,  "hp_mult": 1.0,  "regen": 2, "color": Color("#66bb6a")},
	{"id": "hard",       "name": "어려움",     "sub": "방심하면 위험",   "dmg_mult": 1.7,  "hp_mult": 1.25, "regen": 1, "color": Color("#cddc39")},
	{"id": "extreme",    "name": "익스트림",   "sub": "가혹한 전장",     "dmg_mult": 2.6,  "hp_mult": 1.6,  "regen": 1, "color": Color("#ff9800")},
	{"id": "impossible", "name": "임파서블",   "sub": "한 대도 치명적",  "dmg_mult": 4.0,  "hp_mult": 2.0,  "regen": 0, "color": Color("#f4511e")},
	{"id": "easy_god",   "name": "쉬운 신",    "sub": "神 — 입문",       "dmg_mult": 5.5,  "hp_mult": 2.5,  "regen": 0, "color": Color("#ab47bc")},
	{"id": "normal_god", "name": "보통 신",    "sub": "神 — 분노",       "dmg_mult": 7.5,  "hp_mult": 3.2,  "regen": 0, "color": Color("#9c27b0")},
	{"id": "hard_god",   "name": "어려운 신",  "sub": "神 — 폭주",       "dmg_mult": 10.0, "hp_mult": 4.0,  "regen": 0, "color": Color("#7b1fa2")},
	{"id": "ext_god",    "name": "익스트림 신", "sub": "神 — 재앙",      "dmg_mult": 14.0, "hp_mult": 5.5,  "regen": 0, "color": Color("#5e35b1")},
	{"id": "imp_god",    "name": "임파서블 신", "sub": "神 — 절망",      "dmg_mult": 20.0, "hp_mult": 7.5,  "regen": 0, "color": Color("#311b92")},
]

# ══════════════════════════════════════════════════════════
#  결정론 RNG (core.js: makeRNG) — 저장/리플레이 대비, 기존 빌드와 동일 계열
#  GDScript엔 32비트 unsigned 곱셈 오버플로가 없어 & 0xFFFFFFFF 로 맞춘다.
# ══════════════════════════════════════════════════════════
class RNG:
	var s: int
	func _init(seed_val: int) -> void:
		s = seed_val & 0xFFFFFFFF
		if s == 0:
			s = 12345
	func next() -> float:
		# LCG: (s * 1664525 + 1013904223) >>> 0  /  4294967296
		s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
		return float(s) / 4294967296.0
	func range_f(a: float, b: float) -> float:
		return a + next() * (b - a)
	func int_r(a: int, b: int) -> int:
		return int(floor(range_f(float(a), float(b + 1))))

func make_rng(seed_val: int) -> RNG:
	return RNG.new(seed_val)

# core.js: clamp (Godot에 clamp 내장이 있으나 동일 의미 헬퍼 제공)
func core_clamp(v: float, a: float, b: float) -> float:
	return clampf(v, a, b)

# ══════════════════════════════════════════════════════════
#  공식 함수 (core.js: pickEnemyType / rollRarity / tryDrop)
# ══════════════════════════════════════════════════════════

# 레벨/지역에 따라 적 타입 결정 (core.js: pickEnemyType)
func pick_enemy_type(rng: RNG, lvl: int, region_enemies = null) -> String:
	# 지역별 적 풀이 주어지면 그 안에서 고른다 (지도 해금 시스템)
	if region_enemies != null and region_enemies.size() > 0:
		return region_enemies[int(floor(rng.next() * region_enemies.size()))]
	# 레거시 폴백: 레벨 기반 풀 (강한 적 비율↑)
	var pool := ["slime", "slime", "rat"]
	if lvl >= 2:
		pool.append_array(["pig", "crow"])
	if lvl >= 3:
		pool.append_array(["toad", "hedgehog"])
	if lvl >= 4:
		pool.append("boar")
	if lvl >= 5:
		pool.append("croc")
	if lvl >= 6:
		pool.append_array(["wolf", "boar", "croc"])
	return pool[int(floor(rng.next() * pool.size()))]

# 희귀도 결정 (core.js: rollRarity)
func roll_rarity(rng: RNG, min_r: int = 0) -> int:
	for r in range(4, min_r - 1, -1):
		if rng.next() < float(RARITY_TABLE[r]["chance"]):
			return r
	return min_r

# 드랍 시도 (core.js: tryDrop) — ~12% 확률, is_boss면 희귀(rarity>=2) 보장
# 반환: null(드랍 없음) 또는 {"x", "y", "item_id", "t"}
func try_drop(rng: RNG, ex: float, ey: float, is_boss: bool = false):
	if not is_boss and rng.next() > 0.12:
		return null
	var rarity := roll_rarity(rng, 2 if is_boss else 0)
	# no_drop(전직 전용) 장비는 드랍 풀에서 제외 — 전직으로만 얻는다.
	var pool: Array = []
	for id in ITEM_DEFS.keys():
		var item: Dictionary = ITEM_DEFS[id]
		if int(item["rarity"]) == rarity and not item.get("no_drop", false):
			pool.append(id)
	if pool.is_empty():
		return null
	var item_id: String = pool[rng.int_r(0, pool.size() - 1)]
	return {"x": ex, "y": ey, "item_id": item_id, "t": 0.0}
