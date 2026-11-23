extends RefCounted
## Deterministic, reach-limited candidates for optional bulk PvE scavenging.
## The client sends no bag IDs; special and unowned bags remain manual.
const Defs = preload("res://scripts/shared/defs.gd")
const LootRights = preload("res://scripts/shared/loot_rights.gd")

const MAX_BAGS := 5
const COOLDOWN := 1.5
const RADIUS := Defs.REACH + 0.5


static func candidates(bags: Dictionary, at: Vector3, player, now: float) -> Array[int]:
	var result: Array[int] = []
	if player == null or not at.is_finite() or not is_finite(now):
		return result
	var origin := Vector2(at.x, at.z)
	# The server only claims up to five bags. Maintain a bounded nearest list
	# instead of sorting the entire visible loot population on every command.
	var nearest: Array[Dictionary] = []
	var max_distance_sq: float = RADIUS * RADIUS
	for key in bags.keys():
		var value: Variant = bags[key]
		if not (key is int) or not (value is Dictionary):
			continue
		var bag: Dictionary = value
		if int(bag.get("id", -1)) != int(key) or \
				not (bag.get("allowed_tokens", null) is Array):
			continue # Non-PvE or unowned full-loot bag.
		if bag.has("raid_reserved_until") or bag.has("raid_round_robin") or \
				bag.has("raid_need_greed") or bag.has("death_recovery_owner") or \
				bool(bag.get("supply_drop", false)):
			continue
		if not LootRights.can_loot(bag, player, now) or \
				not (bag.get("items", {}) is Dictionary) or \
				(bag["items"] as Dictionary).is_empty():
			continue
		var expiry: float = float(bag.get("expires", -1.0))
		var x: float = float(bag.get("x", NAN))
		var z: float = float(bag.get("z", NAN))
		if not is_finite(expiry) or now >= expiry or \
				not is_finite(x) or not is_finite(z):
			continue
		var distance: float = origin.distance_squared_to(Vector2(x, z))
		if distance > max_distance_sq:
			continue
		var id: int = int(key)
		var insert_at: int = nearest.size()
		# Same deterministic ordering as the full sort: distance first, then
		# server-generated bag ID when positions are approximately tied.
		while insert_at > 0:
			var previous: Dictionary = nearest[insert_at - 1]
			var previous_distance: float = float(previous["distance"])
			if is_equal_approx(distance, previous_distance):
				if id >= int(previous["id"]):
					break
			elif distance >= previous_distance:
				break
			insert_at -= 1
		if insert_at < MAX_BAGS:
			nearest.insert(insert_at, {"id": id, "distance": distance})
			if nearest.size() > MAX_BAGS:
				nearest.pop_back()
	for entry in nearest:
		result.append(int(entry["id"]))
	return result
