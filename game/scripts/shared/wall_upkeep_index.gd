extends RefCounted
## Index live owners once per server upkeep pass instead of comparing every
## built wall with every online survivor. Account-owned structures survive
## reconnects; guest structures remain bound to their original peer IDs.

const Structures = preload("res://scripts/shared/structures.gd")


## The only account identifiers stored here are session-local; they are never
## added to network snapshots or serialized world data.
static func live_owners(players: Dictionary, is_alive: Callable) -> Dictionary:
	var peers: Dictionary = {}
	var accounts: Dictionary = {}
	if not is_alive.is_valid():
		return {"peers": peers, "accounts": accounts}
	for survivor in players.values():
		if not bool(is_alive.call(survivor)) or not survivor.position.is_finite():
			continue
		var position := Vector2(survivor.position.x, survivor.position.z)
		peers[survivor.id] = position
		if survivor.user_id != "":
			var positions: Array = accounts.get(survivor.user_id, [])
			positions.append(position)
			accounts[survivor.user_id] = positions
	return {"peers": peers, "accounts": accounts}


static func owner_near(wall: Dictionary, index: Dictionary) -> bool:
	var at := Vector2(float(wall["x"]), float(wall["z"]))
	if not at.is_finite():
		return false
	var limit_sq: float = Structures.UPKEEP_RANGE * Structures.UPKEEP_RANGE
	var account: String = str(wall.get("owner_account", ""))
	if account != "":
		var accounts: Dictionary = index.get("accounts", {})
		var positions: Array = accounts.get(account, [])
		for position in positions:
			if at.distance_squared_to(position) <= limit_sq:
				return true
		return false
	var peers: Dictionary = index.get("peers", {})
	var peer_id: int = int(wall.get("owner", -1))
	if peers.has(peer_id):
		return at.distance_squared_to(peers[peer_id]) <= limit_sq
	return false


## Display threshold affects only the owner's private reminder. Durability and
## authoritative upkeep timing continue using the original world rules.
const WARNING_SECONDS := 60.0 * 60.0


static func needs_attention(wall: Dictionary, now: float) -> bool:
	return is_finite(now) and is_finite(float(wall.get("upkeep_until", INF))) \
		and float(wall.get("upkeep_until", INF)) - now <= WARNING_SECONDS
