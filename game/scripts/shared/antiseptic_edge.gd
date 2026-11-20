extends RefCounted
## Paid, short-lived melee weapon preparation for ordinary infected hunts.
## This does not modify PvP, raid-boss damage or raw weapon item definitions.
const Defs = preload("res://scripts/shared/defs.gd")
const ITEM_ID := "antiseptic_edge_oil"
const SECONDS := 120.0
const DAMAGE_BONUS := 0.20


static func melee_equipped(inventory) -> bool:
	var weapon: String = inventory.weapon
	if weapon.is_empty() or inventory.count(weapon) < 1:
		return false
	var info: Dictionary = Defs.item(weapon)
	return str(info.get("kind", "")) == "weapon" and str(info.get("weapon", "")) == "melee"


static func use_reason(inventory, remaining: float) -> String:
	if not is_finite(remaining) or remaining < 0.0 or remaining > SECONDS:
		return "invalid_state"
	if not melee_equipped(inventory):
		return "need_melee"
	if remaining > 0.0:
		return "already_coated"
	return ""


static func still_valid(inventory, coated_weapon: String, remaining: float,
		alive: bool = true) -> bool:
	return alive and is_finite(remaining) and remaining > 0.0 and remaining <= SECONDS and (
		not coated_weapon.is_empty() and coated_weapon == inventory.weapon and
		melee_equipped(inventory))


## Call only in the authoritative "zombie" hit branch, never PvP.
static func damage(amount: float, inventory, coated_weapon: String,
		remaining: float, infected) -> float:
	if not is_finite(amount) or amount <= 0.0:
		return 0.0
	if infected == null or not infected.is_alive() or infected.raid_boss:
		return amount
	if not still_valid(inventory, coated_weapon, remaining):
		return amount
	return amount * (1.0 + DAMAGE_BONUS)


static func tick(inventory, coated_weapon: String, remaining: float,
		delta: float, alive: bool = true) -> float:
	if not is_finite(delta) or delta < 0.0 or not still_valid(
			inventory, coated_weapon, remaining, alive):
		return 0.0
	return maxf(0.0, remaining - delta)
