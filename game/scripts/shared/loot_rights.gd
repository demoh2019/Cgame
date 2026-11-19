extends RefCounted
## Short-lived, server-owned PvE loot reservations. Player full-loot bags are public.

const RESERVATION_SECONDS := 18.0


## Snapshot the current party when the loot is created. A later party invite
## cannot grant access to an older bag, nor can a client forge this roster.
static func reservation(owner_peer: int, party_members: Array, now: float) -> Dictionary:
	if owner_peer <= 0 or not is_finite(now) or now < 0.0:
		return {}
	var allowed: Array[int] = [owner_peer]
	for member in party_members:
		if member is int and int(member) > 0 and not allowed.has(int(member)):
			allowed.append(int(member))
	return {"allowed_peers": allowed, "reserved_until": now + RESERVATION_SECONDS}


static func reserved(bag: Dictionary, now: float) -> bool:
	return bag.has("allowed_peers") and is_finite(now) and now < float(bag.get("reserved_until", 0.0))


static func can_loot(bag: Dictionary, peer: int, now: float) -> bool:
	if not reserved(bag, now):
		return true
	return (bag.get("allowed_peers", []) as Array).has(peer)


## Only viewer-specific flags travel over the network, never the private roster.
static func visible_state(bag: Dictionary, peer: int, now: float) -> Dictionary:
	var active := reserved(bag, now)
	return {
		"id": bag["id"], "x": bag["x"], "y": bag["y"], "z": bag["z"],
		"reserved": active,
		"can_loot": can_loot(bag, peer, now),
		"reserved_seconds": maxf(0.0, float(bag.get("reserved_until", 0.0)) - now) if active else 0.0,
	}
