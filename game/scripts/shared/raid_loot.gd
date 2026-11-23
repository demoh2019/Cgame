extends RefCounted
## Temporary access control for ONE shared raid boss reward bag.
## World loot remains a single inventory; this never duplicates boss prizes.
## Entitlement identities are server-only, not public replicated player IDs.

const Party = preload("res://scripts/shared/party.gd")
const LOCK_SECONDS := 75.0


static func token(player) -> String:
	if not player.user_id.is_empty():
		return "account:" + player.user_id
	# RefCounted instance IDs prevent a reused guest network peer number
	# from inheriting an earlier disconnected guest's reserved loot.
	return "session:%d" % player.get_instance_id()


## Victory is awarded to the real killing player and same-party survivors
## who contributed a valid equipped-weapon hit in the last assist window.
## No distant spectators, AFK members, cross-zone participants or late joins.
static func eligible(killer, boss, players: Dictionary, parties, world, now: float) -> Array:
	var result: Array = [token(killer)]
	var members: Array = parties.members_of(killer.id)
	if members.size() < 2:
		return result
	var zone: int = world.zone_at(boss.position.x, boss.position.z)
	var group_id: int = parties.group_of(killer.id)
	for peer_id in members:
		if int(peer_id) == killer.id:
			continue
		var member = players.get(int(peer_id))
		if member == null or not member.survival.alive 				or not Party.in_assist_range(member.position, boss.position):
			continue
		if world.zone_at(member.position.x, member.position.z) != zone:
			continue
		var hit: Dictionary = boss.contributors.get(int(peer_id), {})
		if hit.is_empty() or int(hit.get("group", 0)) != group_id 				or now - float(hit.get("time", -INF)) > Party.ASSIST_WINDOW:
			continue
		var weapon: String = str(hit.get("weapon", ""))
		if weapon.is_empty() or member.inventory.count(weapon) < 1:
			continue
		var identity: String = token(member)
		if not result.has(identity):
			result.append(identity)
	return result


static func reserve(bag: Dictionary, identities: Array, now: float) -> void:
	if identities.is_empty() or not is_finite(now):
		return
	bag["raid_reserved_until"] = now + LOCK_SECONDS
	bag["raid_eligible_tokens"] = identities.duplicate()


static func remaining(bag: Dictionary, now: float) -> float:
	if not bag.has("raid_reserved_until"):
		return 0.0
	# A corrupt lock must never be presented as expired to the player.
	var raw_expiry: Variant = bag["raid_reserved_until"]
	if not is_finite(now) or now < 0.0 or not (raw_expiry is float or raw_expiry is int):
		return LOCK_SECONDS
	var expiry: float = float(raw_expiry)
	if not is_finite(expiry):
		return LOCK_SECONDS
	return maxf(0.0, expiry - now)


static func can_open(bag: Dictionary, player, now: float) -> bool:
	if player == null or not is_finite(now) or now < 0.0:
		return false
	if not bag.has("raid_reserved_until"):
		return true
	var allowed: Variant = bag.get("raid_eligible_tokens", null)
	if not (allowed is Array):
		return false
	# Corrupt boss lock timestamps fail closed for strangers, while the
	# original contributors can still recover the physical reward bag.
	if remaining(bag, now) <= 0.0:
		return true
	return token(player) in allowed
