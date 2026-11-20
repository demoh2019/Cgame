extends RefCounted
## Three persistent, account-owned equipment shortcuts for classless role swaps.
## No item is moved, spawned, rented or copied: equip looks only in the
## authoritative carried inventory. Safe-hub access is enforced by GameServer.
const Defs = preload("res://scripts/shared/defs.gd")

const SLOT_COUNT := 3


static func empty_slots() -> Array:
	var result: Array = []
	for i in SLOT_COUNT:
		result.append({})
	return result


static func _valid_item(id: String, expected_kind: String) -> bool:
	return id == "" or str(Defs.item(id).get("kind", "")) == expected_kind


## Persisted data has only item IDs. No quantities, tier overrides, price,
## XP, item creation, or client-provided equipment statistics are trusted.
static func valid_state(state: Variant) -> bool:
	if not (state is Array) or (state as Array).size() != SLOT_COUNT:
		return false
	for slot in state:
		if not (slot is Dictionary):
			return false
		var record: Dictionary = slot
		if record.is_empty():
			continue
		if record.size() != 2 or not record.has("weapon") or not record.has("armor"):
			return false
		if not (record["weapon"] is String) or not (record["armor"] is String):
			return false
		if not _valid_item(str(record["weapon"]), "weapon") or \
				not _valid_item(str(record["armor"]), "armor"):
			return false
		if str(record["weapon"]).is_empty() and str(record["armor"]).is_empty():
			return false
	return true


static func save_slot(state: Array, index: int, carried) -> Dictionary:
	if not valid_state(state):
		return {"ok": false, "reason": "invalid_state"}
	if index < 0 or index >= SLOT_COUNT:
		return {"ok": false, "reason": "invalid_slot"}
	var weapon: String = carried.weapon
	var armor: String = carried.armor
	if weapon.is_empty() and armor.is_empty():
		return {"ok": false, "reason": "nothing_equipped"}
	if not _valid_item(weapon, "weapon") or not _valid_item(armor, "armor"):
		return {"ok": false, "reason": "invalid_equipment"}
	if (not weapon.is_empty() and carried.count(weapon) < 1) or \
			(not armor.is_empty() and carried.count(armor) < 1):
		return {"ok": false, "reason": "missing_items"}
	state[index] = {"weapon": weapon, "armor": armor}
	return {"ok": true, "slot": index, "weapon": weapon, "armor": armor}


static func equip_slot(state: Array, index: int, carried) -> Dictionary:
	if not valid_state(state):
		return {"ok": false, "reason": "invalid_state"}
	if index < 0 or index >= SLOT_COUNT:
		return {"ok": false, "reason": "invalid_slot"}
	var record: Dictionary = state[index]
	if record.is_empty():
		return {"ok": false, "reason": "empty_slot"}
	var weapon: String = str(record["weapon"])
	var armor: String = str(record["armor"])
	# Both checks happen before either equipped ID changes. A lost, sold
	# or banked item makes the entire switch fail with no partial equipment.
	if (not weapon.is_empty() and carried.count(weapon) < 1) or \
			(not armor.is_empty() and carried.count(armor) < 1):
		return {"ok": false, "reason": "missing_items"}
	var changed_weapon: bool = carried.weapon != weapon
	var changed_armor: bool = carried.armor != armor
	carried.weapon = weapon
	carried.armor = armor
	return {"ok": true, "slot": index, "weapon": weapon, "armor": armor,
		"weapon_changed": changed_weapon, "armor_changed": changed_armor}


static func clear_slot(state: Array, index: int) -> Dictionary:
	if not valid_state(state):
		return {"ok": false, "reason": "invalid_state"}
	if index < 0 or index >= SLOT_COUNT:
		return {"ok": false, "reason": "invalid_slot"}
	state[index] = {}
	return {"ok": true, "slot": index}
