extends RefCounted
## A one-off PvE rear strike: only legitimate server-owned melee encounters.
const Defs = preload("res://scripts/shared/defs.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")

const DAMAGE_MULTIPLIER := 1.45
const MAX_DISTANCE := 2.4
const MAX_REAR_DOT := -0.55


static func multiplier(attacker, infected, weapon_id: String) -> float:
	if attacker == null or infected == null:
		return 1.0
	if not attacker.crouching or not attacker.position.is_finite():
		return 1.0
	var noise: float = float(attacker.noise_timer)
	if not is_finite(noise) or noise > 0.0 or not attacker.survival.alive:
		return 1.0
	if float(attacker.survival.bleeding) > 0.0:
		return 1.0
	if weapon_id.is_empty() or attacker.inventory.weapon != weapon_id or (
			attacker.inventory.count(weapon_id) < 1):
		return 1.0
	var weapon: Dictionary = Defs.item(weapon_id)
	if str(weapon.get("kind", "")) != "weapon" or str(weapon.get("weapon", "")) != "melee":
		return 1.0
	if not infected.is_alive() or infected.raid_boss or infected.elite or infected.supply_cache_id >= 0:
		return 1.0
	if infected.state != Zombie.State.IDLE and infected.state != Zombie.State.WANDER:
		return 1.0
	if infected.target_id != -1 or infected.forced_target_id != -1 or not infected.threat.is_empty():
		return 1.0
	if not infected.position.is_finite() or not is_finite(infected.yaw):
		return 1.0
	var behind := Vector2(attacker.position.x - infected.position.x,
			attacker.position.z - infected.position.z)
	var d2: float = behind.length_squared()
	if d2 < 0.01 or d2 > MAX_DISTANCE * MAX_DISTANCE:
		return 1.0
	var facing := Vector2(sin(infected.yaw), cos(infected.yaw))
	if behind.normalized().dot(facing) > MAX_REAR_DOT:
		return 1.0
	return DAMAGE_MULTIPLIER
