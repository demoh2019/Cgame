extends RefCounted
## PvE finisher: server-only target selection after a real infected stun.
## No player ID is sent over the wire and no PvP or raid-boss damage is possible.
const MeleeParry = preload("res://scripts/shared/melee_parry.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const RangedCover = preload("res://scripts/shared/ranged_cover.gd")

const ENERGY_COST := 24.0
const COOLDOWN_SECONDS := 6.0
const ATTACK_LOCK := 0.65
const RECOVERY_SECONDS := 0.45
const DAMAGE_MULTIPLIER := 1.7
const MAX_REACH := 3.9
const FRONT_DOT := 0.30


static func eligible(world, survivor, infected) -> bool:
	if survivor == null or infected == null or not MeleeParry.equipped(survivor.inventory):
		return false
	if not survivor.survival.alive or survivor.mounted:
		return false
	if not infected.is_alive() or infected.raid_boss or infected.stagger_seconds <= 0.0:
		return false
	if not survivor.position.is_finite() or not infected.position.is_finite() or not is_finite(survivor.yaw):
		return false
	var origin := Vector2(survivor.position.x, survivor.position.z)
	var destination := Vector2(infected.position.x, infected.position.z)
	var difference := destination - origin
	var distance_squared: float = difference.length_squared()
	if not is_finite(distance_squared) or distance_squared <= 0.01:
		return false
	var reach: float = minf(MAX_REACH, Combat.weapon_reach(survivor.inventory.weapon) + 0.25)
	if distance_squared > reach * reach:
		return false
	var facing := Vector2(sin(survivor.yaw), cos(survivor.yaw))
	var direction: Vector2 = difference.normalized()
	if facing.dot(direction) < FRONT_DOT:
		return false
	# A constructed barricade or ruin wall invalidates an otherwise close hit.
	return RangedCover.first_blocker_distance(world, origin, direction,
		sqrt(distance_squared)) >= sqrt(distance_squared) - 0.1


static func nearest(world, survivor, zombies: Dictionary):
	var best = null
	var best_distance := INF
	for infected in zombies.values():
		if not eligible(world, survivor, infected):
			continue
		var distance: float = Vector2(survivor.position.x, survivor.position.z).distance_squared_to(
			Vector2(infected.position.x, infected.position.z))
		if distance < best_distance or (is_equal_approx(distance, best_distance) and
				(best == null or infected.id < best.id)):
			best = infected
			best_distance = distance
	return best


static func damage(weapon_id: String, progression, skills) -> float:
	return Combat.weapon_damage(weapon_id) * DAMAGE_MULTIPLIER * (
		progression.combat_damage_multiplier(weapon_id)) * (
		1.0 + skills.bonus("melee_damage"))
