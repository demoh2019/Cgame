extends RefCounted
## PvE Guardian Retribution: a real intercepted infected melee strike briefly
## lets the guardian challenge its source and punish that SAME living enemy.
## Client requests cannot arm or select a retaliation target.

const GuardianTaunt = preload("res://scripts/shared/guardian_taunt.gd")
const COUNTER_SECONDS := 4.0
const TAUNT_SECONDS := 1.5
const DAMAGE_MULTIPLIER := 1.25


static func clear(guardian) -> void:
	guardian.guard_counter_target = -1
	guardian.guard_counter_seconds = 0.0
	guardian.guard_counter_weapon = ""
	guardian.guard_counter_party = 0


## Arm only in the authoritative, already-confirmed melee interception path.
static func arm(guardian, infected, parties, world) -> bool:
	if guardian == null or infected == null or parties == null or world == null or \
			not guardian.survival.alive or not infected.is_alive() or \
			not guardian.position.is_finite() or not infected.position.is_finite() or \
			guardian.mounted or not GuardianTaunt.melee_equipped(guardian.inventory):
		return false
	var group: int = parties.group_of(guardian.id)
	if group <= 0 or world.is_safe(guardian.position.x, guardian.position.z) or \
			world.zone_at(guardian.position.x, guardian.position.z) != \
			world.zone_at(infected.position.x, infected.position.z):
		return false
	guardian.guard_counter_target = infected.id
	guardian.guard_counter_seconds = COUNTER_SECONDS
	guardian.guard_counter_weapon = guardian.inventory.weapon
	guardian.guard_counter_party = group
	return true


## First server-accepted normal melee swing consumes the window, EVEN on a
## miss or another target. No ranged attacks, PvP or fake equipment can
## spend the buff as a successful counterstrike. Expiration is tick-driven.
static func consume(guardian, infected, parties, world) -> bool:
	if guardian == null or guardian.guard_counter_seconds <= 0.0:
		return false
	var valid: bool = infected != null and infected.is_alive() and \
			infected.id == guardian.guard_counter_target and \
			guardian.survival.alive and not guardian.mounted and \
			guardian.position.is_finite() and infected.position.is_finite() and \
			GuardianTaunt.melee_equipped(guardian.inventory) and \
			guardian.inventory.weapon == guardian.guard_counter_weapon and \
			guardian.guard_counter_party > 0 and \
			guardian.guard_counter_party == parties.group_of(guardian.id) and \
			not world.is_safe(guardian.position.x, guardian.position.z) and \
			world.zone_at(guardian.position.x, guardian.position.z) == \
			world.zone_at(infected.position.x, infected.position.z)
	clear(guardian)
	return valid


static func amplify(damage: float) -> float:
	if not is_finite(damage) or damage <= 0.0:
		return 0.0
	return damage * DAMAGE_MULTIPLIER
