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
	var ordered: Array[Dictionary] = []
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
		if distance > RADIUS * RADIUS:
			continue
		# Keep only the closest five bags, rather than sorting every world bag.
		# Exact distance and stable ID ties form a transitive ordering.
		var insert_at: int = ordered.size()
		for i in ordered.size():
			var existing: Dictionary = ordered[i]
			var existing_distance: float = float(existing["distance"])
			if distance < existing_distance or (distance == existing_distance and int(key) < int(existing["id"])):
				insert_at = i
				break
		if insert_at >= MAX_BAGS:
			continue
		ordered.insert(insert_at, {"id": int(key), "distance": distance})
		if ordered.size() > MAX_BAGS:
			ordered.pop_back()
	for entry in ordered:
		result.append(int(entry["id"]))
	return result
