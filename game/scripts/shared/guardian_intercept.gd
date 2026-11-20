extends RefCounted
## PvE guardian intercept: block one infected MELEE blow for one party ally.
## Enemy attack, the protected target and actual damage remain server-owned.
const GuardianTaunt = preload("res://scripts/shared/guardian_taunt.gd")

const RANGE := 4.5
const MAX_HEIGHT := 3.0
const DURATION := 9.0
const COOLDOWN := 28.0
const ENERGY_COST := 20.0
const REDIRECT_FRACTION := 0.65


static func can_guard(guardian, ally, parties, world) -> bool:
	if guardian == null or ally == null or world == null or \
			guardian.id == ally.id or not guardian.survival.alive or \
			not ally.survival.alive or guardian.mounted or ally.mounted or \
			not guardian.position.is_finite() or not ally.position.is_finite():
		return false
	if not GuardianTaunt.melee_equipped(guardian.inventory):
		return false
	var group_id: int = parties.group_of(guardian.id)
	if group_id <= 0 or group_id != parties.group_of(ally.id):
		return false
	if world.is_safe(guardian.position.x, guardian.position.z) or \
			world.is_safe(ally.position.x, ally.position.z):
		return false
	if world.zone_at(guardian.position.x, guardian.position.z) != \
			world.zone_at(ally.position.x, ally.position.z):
		return false
	if absf(guardian.position.y - ally.position.y) > MAX_HEIGHT:
		return false
	var delta := Vector2(guardian.position.x - ally.position.x,
		guardian.position.z - ally.position.z)
	return delta.length_squared() <= RANGE * RANGE


static func can_intercept(guardian, ally, parties, world) -> bool:
	return guardian != null and ally != null and \
		guardian.guard_link_target == ally.id and guardian.guard_link_seconds > 0.0 and \
		can_guard(guardian, ally, parties, world)


static func damage(raw_damage: float) -> float:
	if not is_finite(raw_damage) or raw_damage <= 0.0:
		return 0.0
	return raw_damage * REDIRECT_FRACTION
