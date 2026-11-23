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
	if not bag.has("allowed_tokens"):
		return false
	# Corrupt timestamps cannot silently turn a private PvE drop public.
	if not is_finite(now) or now < 0.0:
		return true
	var timestamp: Variant = bag.get("reserved_until", null)
	if not (timestamp is float or timestamp is int):
		return true
	var expiry: float = float(timestamp)
	return not is_finite(expiry) or now < expiry


static func can_loot(bag: Dictionary, player, now: float) -> bool:
	if player == null or not is_finite(now) or now < 0.0:
		return false
	if not bag.has("allowed_tokens"):
		return true
	var tokens: Variant = bag.get("allowed_tokens", null)
	if not (tokens is Array):
		return false
	if not reserved(bag, now):
		return true
	return RaidLoot.token(player) in tokens


## Only viewer-specific flags travel over the network, never identities.
static func visible_state(bag: Dictionary, player, now: float) -> Dictionary:
	var active: bool = reserved(bag, now)
	var remaining: float = 0.0
	if active and is_finite(now):
		var expires_at: Variant = bag.get("reserved_until", null)
		if expires_at is float or expires_at is int:
			var expiry: float = float(expires_at)
			if is_finite(expiry):
				remaining = maxf(0.0, expiry - now)
	return {
		"id": bag["id"], "x": bag["x"], "y": bag["y"], "z": bag["z"],
		"reserved": active,
		"can_loot": can_loot(bag, player, now),
		"reserved_seconds": remaining,
	}
