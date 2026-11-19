extends RefCounted
## Set synergy: a fully equipped relic warden shares limited PvE-only wound
## protection with nearby living party allies. All checks run on the server.
## No player commands, client-owned buff flags, stacking or PvP modifiers.
const Defs = preload("res://scripts/shared/defs.gd")
const RADIUS := 8.0
const HEIGHT_LIMIT := 2.5
const WOUND_REDUCTION := 0.15
const WEAPON_ID := "purifier_maul_3"
const ARMOR_ID := "warden_jacket_3"


static func carries_set(player) -> bool:
	if player == null or not player.survival.alive:
		return false
	if player.inventory.weapon != WEAPON_ID or player.inventory.armor != ARMOR_ID:
		return false
	return player.inventory.count(WEAPON_ID) > 0 and player.inventory.count(ARMOR_ID) > 0


static func active_for(recipient, players: Dictionary, parties, world) -> bool:
	if recipient == null or not recipient.survival.alive or not recipient.position.is_finite():
		return false
	var party_id: int = parties.group_of(recipient.id)
	if party_id == 0:
		return false
	var position: Vector3 = recipient.position
	if world.is_safe(position.x, position.z):
		return false
	var zone: int = world.zone_at(position.x, position.z)
	for raw_id in parties.members_of(recipient.id):
		var peer_id: int = int(raw_id)
		if peer_id == recipient.id:
			continue # The set's wearer gets normal jacket protection, not their own aura.
		var guardian = players.get(peer_id)
		if not carries_set(guardian) or not guardian.position.is_finite():
			continue
		if parties.group_of(guardian.id) != party_id:
			continue
		var at: Vector3 = guardian.position
		if world.is_safe(at.x, at.z) or world.zone_at(at.x, at.z) != zone:
			continue
		if absf(at.y - position.y) > HEIGHT_LIMIT:
			continue
		var distance := Vector2(at.x - position.x, at.z - position.z)
		if distance.length_squared() <= RADIUS * RADIUS:
			return true
	return false


static func mitigate_wound(amount: float, active: bool) -> float:
	if not is_finite(amount) or amount <= 0.0:
		return 0.0
	return amount * (1.0 - WOUND_REDUCTION) if active else amount
