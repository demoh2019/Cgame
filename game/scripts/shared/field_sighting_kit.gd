extends RefCounted
## Limited equipment-bound ranged damage preparation for server-verified infected.
const Defs = preload("res://scripts/shared/defs.gd")

const ITEM_ID := "field_sighting_kit"
const HITS := 4
const DAMAGE_FACTOR := 1.12


static func ranged_weapon(inventory) -> String:
	var weapon: String = inventory.weapon
	if weapon.is_empty() or inventory.count(weapon) < 1:
		return ""
	var info: Dictionary = Defs.item(weapon)
	if str(info.get("kind", "")) != "weapon" or str(info.get("weapon", "")) != "ranged":
		return ""
	return weapon


## Reject forged hit counts, invalid weapon IDs, lost and unequipped weapons.
static func valid_state(weapon: Variant, hits: Variant, inventory) -> bool:
	if not (weapon is String) or not (hits is int):
		return false
	if hits < 0 or hits > HITS:
		return false
	if hits == 0:
		return weapon == ""
	return weapon != "" and weapon == ranged_weapon(inventory)


static func bonus_active(weapon: String, hits: int, inventory, actual_weapon: String) -> bool:
	return hits > 0 and weapon == actual_weapon and valid_state(weapon, hits, inventory)
