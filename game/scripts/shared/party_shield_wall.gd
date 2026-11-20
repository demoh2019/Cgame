extends RefCounted
## Cooperative guardian Shield Wall. Only the authoritative server can arm it.
## It mitigates real infected melee damage to OTHER nearby party members.
## No PvP, acid, AoE or environmental branch calls this helper.
const GuardianTaunt = preload("res://scripts/shared/guardian_taunt.gd")

const RADIUS := 5.5
const MAX_HEIGHT := 3.0
const DURATION := 6.0
const COOLDOWN := 32.0
const ENERGY_COST := 30.0
const DAMAGE_REDUCTION := 0.22
const RAID_DAMAGE_REDUCTION := 0.12


## Validate again at every melee hit. Position, gear, party and safety are
## real server values, not data supplied by a requesting client.
static func can_protect(guardian, ally, parties, world) -> bool:
	if guardian == null or ally == null or parties == null or world == null or \
			guardian.id == ally.id or not guardian.survival.alive or \
			not ally.survival.alive or guardian.mounted or ally.mounted or \
			not guardian.position.is_finite() or not ally.position.is_finite():
		return false
	if not GuardianTaunt.melee_equipped(guardian.inventory):
		return false
	var party_id: int = parties.group_of(guardian.id)
	if party_id <= 0 or party_id != parties.group_of(ally.id):
		return false
	if world.is_safe(guardian.position.x, guardian.position.z) or \
			world.is_safe(ally.position.x, ally.position.z):
		return false
	if world.zone_at(guardian.position.x, guardian.position.z) != \
			world.zone_at(ally.position.x, ally.position.z):
		return false
	if absf(guardian.position.y - ally.position.y) > MAX_HEIGHT:
		return false
	var offset := Vector2(guardian.position.x - ally.position.x,
		guardian.position.z - ally.position.z)
	return offset.length_squared() <= RADIUS * RADIUS


## Bounded to current party roster (<=5); deterministic tie-breaker when
## multiple guardians overlap. Stronger armor does not stack their auras.
static func protector_for(ally, players: Dictionary, parties, world) -> int:
	if ally == null or not ally.survival.alive:
		return -1
	var best_id: int = -1
	var best_distance: float = INF
	for id in parties.members_of(ally.id):
		var guardian = players.get(int(id))
		if guardian == null or guardian.shield_wall_seconds <= 0.0 or \
				not can_protect(guardian, ally, parties, world):
			continue
		var distance: float = guardian.position.distance_squared_to(ally.position)
		if distance < best_distance - 0.001 or (absf(distance - best_distance) <= 0.001 and \
				(best_id < 0 or guardian.id < best_id)):
			best_id = guardian.id
			best_distance = distance
	return best_id


## Flat percentage after armor, Dodge, Brace and Parry; wounds keep their
## original wound-resistance rules and are not healed or erased by this buff.
static func mitigate(damage: float, raid_boss: bool) -> float:
	if not is_finite(damage) or damage <= 0.0:
		return 0.0
	return damage * (1.0 - (RAID_DAMAGE_REDUCTION if raid_boss else DAMAGE_REDUCTION))
