extends RefCounted
## Per-broadcast wall interest and private owner status aggregation. Never
## persisted or sent as a whole: only the viewer's own summary is replicated.
## A stock Godot server uses the same GDScript path without native modules.

const Structures = preload("res://scripts/shared/structures.gd")
const WallUpkeepIndex = preload("res://scripts/shared/wall_upkeep_index.gd")
const TILE_SIZE := 64.0
const MAX_QUERY_CELLS := 256


static func _empty_summary() -> Dictionary:
	return {"at_risk": 0, "damaged": 0, "under_attack": 0,
		"soonest_seconds": INF, "attack_until": -INF,
		"attack_x": 0.0, "attack_z": 0.0}


## One pass over wall state, shared across all recipients of a synchronous
## broadcast. Coordinates use wall centres, exactly like the legacy filter.
static func build(walls: Dictionary, now: float, infected_attacks: Dictionary) -> Dictionary:
	var entries: Array = []
	var tiles: Dictionary = {}
	var accounts: Dictionary = {}
	var guests: Dictionary = {}
	for wall in walls.values():
		var slot: int = entries.size()
		entries.append(wall)
		var x: float = float(wall["x"])
		var z: float = float(wall["z"])
		if is_finite(x) and is_finite(z):
			var cell := Vector2i(floori(x / TILE_SIZE), floori(z / TILE_SIZE))
			var bucket: Array = tiles.get(cell, [])
			bucket.append(slot)
			tiles[cell] = bucket
		var account: String = str(wall.get("owner_account", ""))
		var peer_id: int = int(wall.get("owner", -1))
		if account == "" and peer_id < 0:
			continue
		var target: Dictionary = accounts if account != "" else guests
		var owner_key: Variant = account if account != "" else peer_id
		var state: Dictionary = target.get(owner_key, _empty_summary())
		if WallUpkeepIndex.needs_attention(wall, now):
			state["at_risk"] = int(state["at_risk"]) + 1
			state["soonest_seconds"] = minf(float(state["soonest_seconds"]),
				maxf(0.0, float(wall["upkeep_until"]) - now))
		if float(wall["hp"]) < Structures.max_health(Structures.tier_of(wall)) * 0.5:
			state["damaged"] = int(state["damaged"]) + 1
		var alert_until: float = float(infected_attacks.get(int(wall["id"]), -INF))
		if is_finite(alert_until) and alert_until > now:
			state["under_attack"] = int(state["under_attack"]) + 1
			# The most recently hit wall provides an actionable private
			# direction, even when the base is outside snapshot interest.
			if alert_until > float(state["attack_until"]) and is_finite(x) and is_finite(z):
				state["attack_until"] = alert_until
				state["attack_x"] = x
				state["attack_z"] = z
		target[owner_key] = state
	return {"entries": entries, "tiles": tiles, "accounts": accounts, "guests": guests}


## Preserve the former public payload and insertion order. A wide / invalid
## query falls back to the original exhaustive scan rather than hiding walls.
static func visible(index: Dictionary, at: Vector2, radius: float) -> Array:
	var result: Array = []
	var entries: Array = index["entries"]
	if not at.is_finite() or not is_finite(radius) or radius < 0.0:
		return result
	var from := Vector2i(floori((at.x - radius) / TILE_SIZE),
		floori((at.y - radius) / TILE_SIZE))
	var to := Vector2i(floori((at.x + radius) / TILE_SIZE),
		floori((at.y + radius) / TILE_SIZE))
	var columns: int = to.x - from.x + 1
	var rows: int = to.y - from.y + 1
	if (columns <= 0 or rows <= 0 or columns > MAX_QUERY_CELLS
			or rows > MAX_QUERY_CELLS or columns * rows > MAX_QUERY_CELLS):
		for wall in entries:
			if Structures.within_range(at, Vector2(float(wall["x"]), float(wall["z"])), radius):
				result.append(wall)
		return result
	var selected: Array[int] = []
	var tiles: Dictionary = index["tiles"]
	for x in range(from.x, to.x + 1):
		for z in range(from.y, to.y + 1):
			var bucket: Array = tiles.get(Vector2i(x, z), [])
			for raw_slot in bucket:
				var slot: int = int(raw_slot)
				var wall: Dictionary = entries[slot]
				if Structures.within_range(at,
						Vector2(float(wall["x"]), float(wall["z"])), radius):
					selected.append(slot)
	selected.sort()
	for slot in selected:
		result.append(entries[slot])
	return result


## Combine the account and legacy guest-peer ownership categories without
## exposing accounts or stale coordinates to another player.
static func private_status(index: Dictionary, peer_id: int, user_id: String) -> Dictionary:
	var combined: Dictionary = _empty_summary()
	var parts: Array = []
	var guests: Dictionary = index["guests"]
	if guests.has(peer_id):
		parts.append(guests[peer_id])
	var accounts: Dictionary = index["accounts"]
	if user_id != "" and accounts.has(user_id):
		parts.append(accounts[user_id])
	for state in parts:
		combined["at_risk"] = int(combined["at_risk"]) + int(state["at_risk"])
		combined["damaged"] = int(combined["damaged"]) + int(state["damaged"])
		combined["under_attack"] = int(combined["under_attack"]) + int(state["under_attack"])
		combined["soonest_seconds"] = minf(float(combined["soonest_seconds"]),
			float(state["soonest_seconds"]))
		if float(state["attack_until"]) > float(combined["attack_until"]):
			combined["attack_until"] = float(state["attack_until"])
			combined["attack_x"] = float(state["attack_x"])
			combined["attack_z"] = float(state["attack_z"])
	var result: Dictionary = {"at_risk": int(combined["at_risk"]),
		"damaged": int(combined["damaged"]),
		"under_attack": int(combined["under_attack"]),
		"soonest_seconds": float(combined["soonest_seconds"])
			if int(combined["at_risk"]) > 0 else 0.0}
	if int(combined["under_attack"]) > 0 and float(combined["attack_until"]) > -INF:
		result["attack_x"] = float(combined["attack_x"])
		result["attack_z"] = float(combined["attack_z"])
	return result
