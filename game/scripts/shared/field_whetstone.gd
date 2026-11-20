extends RefCounted
## Paid, limited melee preparation. Pure rules used by the server and save loader.

const Defs = preload("res://scripts/shared/defs.gd")

const ITEM_ID := "field_whetstone"
const HITS := 3
const DAMAGE_FACTOR := 1.15


static func melee_weapon(inventory) -> String:
	var weapon: String = inventory.weapon
	if weapon.is_empty() or inventory.count(weapon) < 1:
		return ""
	var info: Dictionary = Defs.item(weapon)
	if str(info.get("kind", "")) != "weapon" or str(info.get("weapon", "")) != "melee":
		return ""
	return weapon


## Strictly reject invalid persisted charges and equipment ownership.
static func valid_state(weapon: Variant, hits: Variant, inventory) -> bool:
	if not (weapon is String) or not (hits is int):
		return false
	if hits < 0 or hits > HITS:
		return false
	if hits == 0:
		return weapon == ""
	return weapon != "" and weapon == melee_weapon(inventory)


static func bonus_active(weapon: String, hits: int, inventory, attack_weapon: String) -> bool:
	return hits > 0 and weapon == attack_weapon and valid_state(weapon, hits, inventory)
