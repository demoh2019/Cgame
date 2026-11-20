extends RefCounted
## Explicit team call for a real *public* death bag, not an extra loot right.
## The owner, bag, group and expiration are all server-authenticated.
const DeathRecovery = preload("res://scripts/shared/death_recovery.gd")
const RaidLoot = preload("res://scripts/shared/raid_loot.gd")

const SECONDS := 90.0
const COOLDOWN := 18.0


static func request(player, parties, bags: Dictionary, now: float) -> Dictionary:
	if player == null or not is_finite(now):
		return {"ok": false, "reason": "unknown_player"}
	var group_id: int = parties.group_of(player.id)
	if group_id <= 0 or not parties.groups.has(group_id):
		return {"ok": false, "reason": "not_in_party"}
	var group: Dictionary = parties.groups[group_id]
	if group["members"].size() < 2 or not group["members"].has(player.id):
		return {"ok": false, "reason": "need_party"}
	var target: Dictionary = DeathRecovery.public_mark(bags, player, now)
	if target.is_empty():
		return {"ok": false, "reason": "no_recoverable_bag"}
	var token: String = RaidLoot.token(player)
	var id: int = -1
	for bag_id in bags:
		var bag: Dictionary = bags[bag_id]
		if str(bag.get("death_recovery_owner", "")) != token:
			continue
		if float(bag.get("x", INF)) == float(target["x"]) and \
				float(bag.get("z", INF)) == float(target["z"]) and \
				float(bag.get("expires", -INF)) > now and \
				int(bag.get("id", -1)) > id:
			id = int(bag["id"])
	if id < 0:
		return {"ok": false, "reason": "no_recoverable_bag"}
	var old: Dictionary = group.get("corpse_rescue", {})
	if not old.is_empty() and int(old.get("bag", -1)) == id and \
			int(old.get("by", -1)) == player.id and \
			float(old.get("until", 0.0)) > now:
		return {"ok": false, "reason": "already_shared"}
	if now < float(group.get("corpse_rescue_last_at", -INF)) + COOLDOWN:
		return {"ok": false, "reason": "cooldown"}
	group["corpse_rescue_last_at"] = now
	group["corpse_rescue"] = {"bag": id, "by": player.id, "owner_token": token,
		"until": minf(now + SECONDS, float(bags[id]["expires"]))}
	return {"ok": true, "seconds": float(group["corpse_rescue"]["until"]) - now}


## Generate the preview for each actual current group member separately.
## When the author leaves or a bag is stolen, the marker vanishes at once.
static func shared(peer_id: int, players: Dictionary, parties,
		bags: Dictionary, now: float) -> Dictionary:
	if not players.has(peer_id) or not is_finite(now):
		return {}
	var group_id: int = parties.group_of(peer_id)
	if group_id <= 0 or not parties.groups.has(group_id):
		return {}
	var group: Dictionary = parties.groups[group_id]
	if not group["members"].has(peer_id):
		return {}
	var signal: Dictionary = group.get("corpse_rescue", {})
	if signal.is_empty() or now >= float(signal.get("until", 0.0)):
		return {}
	var sender: int = int(signal.get("by", -1))
	if not players.has(sender) or not group["members"].has(sender) or \
			parties.group_of(sender) != group_id or \
			RaidLoot.token(players[sender]) != str(signal.get("owner_token", "")):
		return {}
	var bag_id: int = int(signal.get("bag", -1))
	var physical: Dictionary = bags.get(bag_id, {})
	if physical.is_empty() or str(physical.get("death_recovery_owner", "")) != \
			str(signal.get("owner_token", "")):
		return {}
	var mark: Dictionary = DeathRecovery.public_mark({bag_id: physical},
		players[sender], now)
	if mark.is_empty():
		return {}
	return {"by": sender, "x": float(mark["x"]), "z": float(mark["z"]),
		"remaining": minf(float(mark["remaining"]),
			float(signal["until"]) - now)}
