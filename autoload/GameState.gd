extends Node
## GameState — 플레이어 상태(core.js: freshPlayer)와 게임 진행을 담는 단일 정본(autoload 싱글톤).
## mino1 의 this.gs(게임상태 객체)에 해당. 저장/복원은 user://save.json 으로.

const SAVE_PATH := "user://save.json"

# 플레이어 상태 (core.js: freshPlayer() 그대로). mino1 키 이름 보존.
var player: Dictionary = {}

# 게임 진행 (mino1 this.gs 의 나머지 — 단계 진행하며 채운다)
var region: int = 0           # 현재 지역 인덱스 (0=들판)
var difficulty: int = -1      # 난이도 인덱스 (-1=미선택, DIFFICULTY_DEFS 인덱스)
var inventory: Array = []     # 보유 장비 [{item_id, rarity}, ...]
var unlocked_regions: int = 1 # 해금된 지역 수 (보스 잡으면 +1)
var seed_val: int = 12345     # 결정론 RNG 시드


func _ready() -> void:
	# 시작 시 저장이 있으면 불러오고, 없으면 새 플레이어로.
	if not load_game():
		player = fresh_player()


# core.js: freshPlayer() — 플레이어 기본 스탯. 키 이름 1:1 보존.
func fresh_player() -> Dictionary:
	return {
		"x": GameData.WORLD_W / 2.0, "y": GameData.WORLD_H / 2.0, "r": 22,
		"sp": 165, "hp": 100, "maxhp": 100,
		"lvl": 1, "xp": 0, "xpNext": 20, "kills": 0,
		"atkPow": 11, "atkSpeed": 0.5, "atkRange": 64, "atkCD": 0.0,
		"inv": 0.0,            # 피격 무적 타이머
		"mp": 100, "maxmp": 100, "armor": 0, "cdMult": 1.0,
		"face": 1,             # 바라보는 방향(+1 오른쪽 / -1 왼쪽)
		"skills": {},
		"equip": {"weapon": null, "armor": null, "accessory": null},
		"statPoints": 0,       # 스탯 포인트 (레벨업마다 +3)
		"xpGainMult": 1.0,     # 경험치 획득량 배수
		# 스탯 포인트 투자 누적 (저장/복원용)
		"spentStats": {"atkPow": 0, "armor": 0, "maxhp": 0, "maxmp": 0, "sp": 0, "atkSpeed": 0, "xpGain": 0},
		"gold": 0,             # 보유 골드
		"job": null,           # 1차 전직
		"job2": null,          # 2차 전직 (Lv25)
	}


# 새 게임 시작 (난이도 등 진행도 초기화)
func new_game(difficulty_idx: int = 1) -> void:
	player = fresh_player()
	region = 0
	difficulty = difficulty_idx
	inventory = []
	unlocked_regions = 1
	save_game()


# ── 저장 (mino1: localStorage → Godot: user://save.json) ──────
func save_game() -> bool:
	var data := {
		"player": player,
		"region": region,
		"difficulty": difficulty,
		"inventory": inventory,
		"unlocked_regions": unlocked_regions,
		"seed_val": seed_val,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("save.json 열기 실패: %s" % FileAccess.get_open_error())
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true


# ── 복원 ──────────────────────────────────────────────────
# 성공 시 true, 저장 없음/손상이면 false (호출부가 fresh_player로 폴백).
func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	# 누락 키는 fresh 기본값으로 채워 안전하게 합친다.
	var base := fresh_player()
	var saved_player = parsed.get("player", {})
	if typeof(saved_player) == TYPE_DICTIONARY:
		for k in saved_player.keys():
			base[k] = saved_player[k]
	player = base
	region = int(parsed.get("region", 0))
	difficulty = int(parsed.get("difficulty", -1))
	inventory = parsed.get("inventory", [])
	unlocked_regions = int(parsed.get("unlocked_regions", 1))
	seed_val = int(parsed.get("seed_val", 12345))
	return true


# 저장 삭제 (처음부터 등에서 사용)
func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
