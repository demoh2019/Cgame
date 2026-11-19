extends RefCounted
## Short-lived, server-owned PvE loot reservations. Player full-loot bags are public.

const RaidLoot = preload("res://scripts/shared/raid_loot.gd")
const RESERVATION_SECONDS := 18.0


## Freeze actual Player identities at the moment of the kill.
## Accounts survive reconnect; guests are tied to one RefCounted session instance,
## so a reused network peer number cannot steal loot from a disconnected survivor.
static func reservation(participants: Array, now: float) -> Dictionary:
	if participants.is_empty() or not is_finite(now) or now < 0.0:
		return {}
	var allowed: Array[String] = []
	for player in participants:
		if player == null:
			continue
		var identity: String = RaidLoot.token(player)
		if not allowed.has(identity):
			allowed.append(identity)
	if allowed.is_empty():
		return {}
	return {"allowed_tokens": allowed, "reserved_until": now + RESERVATION_SECONDS}


static func reserved(bag: Dictionary, now: float) -> bool:
	return bag.has("allowed_tokens") and is_finite(now) and now < float(bag.get("reserved_until", 0.0))


static func can_loot(bag: Dictionary, player, now: float) -> bool:
	if not reserved(bag, now):
		return true
	return RaidLoot.token(player) in bag.get("allowed_tokens", [])


## Only viewer-specific flags travel over the network, never identities.
static func visible_state(bag: Dictionary, player, now: float) -> Dictionary:
	var active := reserved(bag, now)
	return {
		"id": bag["id"], "x": bag["x"], "y": bag["y"], "z": bag["z"],
		"reserved": active,
		"can_loot": can_loot(bag, player, now),
		"reserved_seconds": maxf(0.0, float(bag.get("reserved_until", 0.0)) - now) if active else 0.0,
	}
