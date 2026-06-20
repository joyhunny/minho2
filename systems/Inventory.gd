extends Node
class_name InventorySystem
## InventorySystem — 장비 장착/해제·줍기·판매의 단일 권한(SSOT). mino1 _equipItem/_unequipItem 대응.
## mino1 의 this._inventory(보유 장비 배열) = GameState.inventory, this.gs.player.equip = GameState.player.equip.
## ★S3 핸드오프 약속: 무기 스탯 합산 로직을 JobPanel 에서 *여기로 이관*한다(equip/unequip 단일 권한).
## 밸런스(아이템 스탯·골드 판매가)는 GameData(=mino1 core.js) 값을 그대로 쓴다.

const INV_MAX := 16            # mino1 _INV_MAX = 16

var main: Node = null


# ── 장착 (같은 슬롯이면 기존 것 먼저 해제) (mino1 _equipItem) ──
# 반환: 교체되어 빠진 이전 아이템 id (없으면 "")
func equip(slot: String, item_id: String) -> String:
	if not GameData.ITEM_DEFS.has(item_id):
		return ""
	var p: Dictionary = GameState.player
	var equip_d: Dictionary = p.get("equip", {})
	var prev := ""
	if equip_d.get(slot, null) != null:
		prev = str(equip_d[slot])
		unequip(slot)
		equip_d = p.get("equip", {})
	equip_d[slot] = item_id
	p["equip"] = equip_d
	_apply_stats(GameData.ITEM_DEFS[item_id].get("stats", {}), p, 1.0)
	return prev


# ── 해제 (mino1 _unequipItem) — 슬롯 비우고 스탯 차감 ──
func unequip(slot: String) -> void:
	var p: Dictionary = GameState.player
	var equip_d: Dictionary = p.get("equip", {})
	var item_id = equip_d.get(slot, null)
	if item_id == null:
		return
	equip_d[slot] = null
	p["equip"] = equip_d
	_apply_stats(GameData.ITEM_DEFS[str(item_id)].get("stats", {}), p, -1.0)


# 아이템 스탯을 플레이어에 더하거나(sign=+1) 뺀다(sign=-1).
# mino1: maxhp 는 현재 hp 도 같이 올리고(장착 시), 해제 시엔 hp 를 maxhp 로 클램프.
func _apply_stats(stats: Dictionary, p: Dictionary, sign_v: float) -> void:
	for key in stats.keys():
		var v := float(stats[key])
		if key == "maxhp":
			p["maxhp"] = float(p.get("maxhp", 0)) + v * sign_v
			if sign_v > 0.0:
				p["hp"] = minf(float(p["maxhp"]), float(p.get("hp", 0)) + v)
			else:
				p["hp"] = minf(float(p["maxhp"]), float(p.get("hp", 0)))
		else:
			p[key] = float(p.get(key, 0)) + v * sign_v


# ── 인벤토리에 아이템 추가 (mino1 this._inventory.push) — 가득 차면 false ──
func add_to_bag(item_id: String) -> bool:
	if GameState.inventory.size() >= INV_MAX:
		return false
	GameState.inventory.append({"item_id": item_id})
	return true


func bag_full() -> bool:
	return GameState.inventory.size() >= INV_MAX


# ── 바닥 아이템 자동 줍기 처리 (mino1 _updateGroundItems 의 픽업 분기) ──
# 빈 슬롯이면 바로 장착, 아니면 가방에. 둘 다 안 되면 false(못 주움).
func pickup(item_id: String) -> bool:
	if not GameData.ITEM_DEFS.has(item_id):
		return false
	var p: Dictionary = GameState.player
	var slot: String = str(GameData.ITEM_DEFS[item_id].get("slot", "weapon"))
	var equip_d: Dictionary = p.get("equip", {})
	if equip_d.get(slot, null) == null:
		equip(slot, item_id)
		if main:
			main.show_pickup_toast("장착: " + str(GameData.ITEM_DEFS[item_id].get("name", item_id)))
		GameState.save_game()
		return true
	elif not bag_full():
		add_to_bag(item_id)
		if main:
			main.show_pickup_toast("획득: " + str(GameData.ITEM_DEFS[item_id].get("name", item_id)))
		GameState.save_game()
		return true
	return false  # 가방 가득 — 안 주움


# ── 판매 (mino1 _handleInvTap 의 팔기 분기) — 희귀도별 골드 ──
# 반환: 받은 골드(없으면 0)
func sell(inv_idx: int) -> int:
	if inv_idx < 0 or inv_idx >= GameState.inventory.size():
		return 0
	var item_id: String = str(GameState.inventory[inv_idx].get("item_id", ""))
	if not GameData.ITEM_DEFS.has(item_id):
		return 0
	var rarity := int(GameData.ITEM_DEFS[item_id].get("rarity", 0))
	var price := int(GameData.GOLD_SELL_PRICE[clampi(rarity, 0, GameData.GOLD_SELL_PRICE.size() - 1)])
	GameState.inventory.remove_at(inv_idx)
	var p: Dictionary = GameState.player
	p["gold"] = int(p.get("gold", 0)) + price
	GameState.save_game()
	return price


# 판매 예상 가격(미리보기용)
func sell_price(item_id: String) -> int:
	if not GameData.ITEM_DEFS.has(item_id):
		return 0
	var rarity := int(GameData.ITEM_DEFS[item_id].get("rarity", 0))
	return int(GameData.GOLD_SELL_PRICE[clampi(rarity, 0, GameData.GOLD_SELL_PRICE.size() - 1)])
