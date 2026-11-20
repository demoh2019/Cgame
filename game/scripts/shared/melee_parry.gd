extends RefCounted
## A timed, one-hit front-facing block for regular infected melee.
## No effect on other survivors, ranged hazards or boss area attacks.

const Defs = preload("res://scripts/shared/defs.gd")

const STAMINA_COST := 20.0
const WINDOW_SECONDS := 0.45
const COOLDOWN_SECONDS := 4.0
const ATTACK_LOCK := 0.35
const DAMAGE_FACTOR := 0.30
const WOUND_FACTOR := 0.30
const STAGGER_SECONDS := 1.0
const MAX_DISTANCE := 2.7
const FRONT_DOT := 0.35


static func equipped(inventory) -> bool:
	var weapon_id: String = inventory.weapon
	if weapon_id.is_empty() or inventory.count(weapon_id) < 1:
		return false
	var item: Dictionary = Defs.item(weapon_id)
	return str(item.get("kind", "")) == "weapon" and str(item.get("weapon", "")) == "melee"


## Both orientation and equipment are checked on the server AT IMPACT.
## Only a real front-facing attack can consume an active parry window.
static func can_block(defender, infected) -> bool:
	if defender == null or infected == null or defender.parry_window <= 0.0:
		return false
	if not defender.survival.alive or defender.mounted or defender.dodge_immunity > 0.0:
		return false
	if infected.raid_boss or not infected.is_alive():
		return false
	if not equipped(defender.inventory):
		return false
	if not defender.position.is_finite() or not infected.position.is_finite() or not is_finite(defender.yaw):
		return false
	var direction := Vector2(infected.position.x - defender.position.x,
		infected.position.z - defender.position.z)
	var distance_squared: float = direction.length_squared()
	if distance_squared < 0.0001 or distance_squared > MAX_DISTANCE * MAX_DISTANCE:
		return false
	var forward := Vector2(sin(defender.yaw), cos(defender.yaw))
	return forward.dot(direction.normalized()) >= FRONT_DOT
