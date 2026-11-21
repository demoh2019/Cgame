extends RefCounted
## Combat healer's emergency cover request: transfers only CURRENT infected aggro
## to one equipped nearby party guardian, with server-only target selection.
## Infected not already fighting/aware of the medic are never provoked.
const Defs = preload("res://scripts/shared/defs.gd")
const GuardianTaunt = preload("res://scripts/shared/guardian_taunt.gd")
const Threat = preload("res://scripts/shared/threat.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")

const RADIUS := 8.0
const ENEMY_RADIUS := 16.0
const MAX_HEIGHT := 3.0
const MAX_ENEMIES := 3
const ENERGY_COST := 24.0
const COOLDOWN := 30.0
const TAUNT_SECONDS := 2.0
const RETAINED_THREAT := 0.35


static func has_staff(medic) -> bool:
	if medic == null:
		return false
	var weapon: String = medic.inventory.weapon
	if not weapon.begins_with("restoration_staff_") or \
			medic.inventory.count(weapon) < 1:
		return false
	var details: Dictionary = Defs.item(weapon)
	return str(details.get("kind", "")) == "weapon" and \
			str(details.get("weapon", "")) == "melee" and \
			int(details.get("tier", 0)) >= 1


static func guardian_ok(medic, guardian, parties, world) -> bool:
	if medic == null or guardian == null or world == null or parties == null or \
			medic.id == guardian.id or not medic.survival.alive or \
			not guardian.survival.alive or medic.mounted or guardian.mounted or \
			not medic.position.is_finite() or not guardian.position.is_finite():
		return false
	if not has_staff(medic) or not GuardianTaunt.melee_equipped(guardian.inventory) or \
			guardian.inventory.weapon.begins_with("restoration_staff_"):
		return false
	var group: int = parties.group_of(medic.id)
	if group <= 0 or group != parties.group_of(guardian.id):
		return false
	if world.is_safe(medic.position.x, medic.position.z) or \
			world.is_safe(guardian.position.x, guardian.position.z):
		return false
	if world.zone_at(medic.position.x, medic.position.z) != \
			world.zone_at(guardian.position.x, guardian.position.z):
		return false
	if absf(medic.position.y - guardian.position.y) > MAX_HEIGHT:
		return false
	var distance := Vector2(medic.position.x - guardian.position.x,
		medic.position.z - guardian.position.z)
	return distance.length_squared() <= RADIUS * RADIUS


## Unique guardian nearest to the caster, stable peer-ID ties.
static func guardian_for(medic, players: Dictionary, parties, world):
	if medic == null:
		return null
	var chosen = null
	var nearest: float = INF
	for id in parties.members_of(medic.id):
		var guardian = players.get(int(id))
		if not guardian_ok(medic, guardian, parties, world):
			continue
		var squared: float = medic.position.distance_squared_to(guardian.position)
		if squared < nearest - 0.001 or (absf(squared - nearest) <= 0.001 and \
				(chosen == null or guardian.id < chosen.id)):
			chosen = guardian
			nearest = squared
	return chosen


## No boss manipulation, idle/wandering pack aggro, other parties, cross-zone
## threats, remote transfers, or overwriting an unrelated active taunt.
static func can_redirect(infected, medic, guardian, world) -> bool:
	if infected == null or medic == null or guardian == null or world == null or \
			not infected.is_alive() or infected.raid_boss or \
			not infected.position.is_finite():
		return false
	if infected.state != Zombie.State.CHASE and infected.state != Zombie.State.ATTACK:
		return false
	if infected.forced_target_seconds > 0.0 and \
			infected.forced_target_id != medic.id:
		return false
	var current: float = float(infected.threat.get(medic.id, 0.0))
	if (not is_finite(current) or current <= 0.0) and infected.target_id != medic.id:
		return false
	if world.is_safe(infected.position.x, infected.position.z) or \
			world.zone_at(infected.position.x, infected.position.z) != \
			world.zone_at(medic.position.x, medic.position.z):
		return false
	if absf(infected.position.y - medic.position.y) > MAX_HEIGHT or \
			absf(infected.position.y - guardian.position.y) > MAX_HEIGHT:
		return false
	var here := Vector2(infected.position.x, infected.position.z)
	var at_medic := Vector2(medic.position.x, medic.position.z)
	var at_guardian := Vector2(guardian.position.x, guardian.position.z)
	var leash: float = float(infected.data.get("lose", 0.0))
	if not is_finite(leash) or leash <= 0.0:
		return false
	var range_allowed: float = minf(leash, ENEMY_RADIUS)
	return here.distance_squared_to(at_medic) <= range_allowed * range_allowed and \
		here.distance_squared_to(at_guardian) <= range_allowed * range_allowed


## Fold only the medic's existing, finite hate. Zombie.force_taunt adds its
## own bounded guardian threat and a short target-lock; no fabricated heals.
static func fade_threat(infected, medic_id: int) -> void:
	# The same bounded native primitive is used by the stock-Godot fallback.
	# No server-unverified target or new threat is introduced here.
	Threat.scale(infected.threat, medic_id, RETAINED_THREAT)
