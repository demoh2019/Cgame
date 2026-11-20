extends RefCounted
## Blood-marked death loot is a temporary location cue for idle infected.
## Only server-confirmed kills may attach a scent to a real loot bag.

const DURATION := 40.0
const RADIUS := 22.0


static func mark(bag: Dictionary, now: float) -> bool:
	if not bag.has("id") or not is_finite(now):
		return false
	var until: float = float(bag.get("expires", -1.0))
	var x: float = float(bag.get("x", NAN))
	var z: float = float(bag.get("z", NAN))
	if not is_finite(until) or until <= now or not is_finite(x) or not is_finite(z):
		return false
	bag["corpse_scent_until"] = minf(until, now + DURATION)
	return true


static func active(bag: Dictionary, now: float) -> bool:
	if not is_finite(now) or not bag.has("id") or not bag.has("corpse_scent_until"):
		return false
	var expiry: float = float(bag.get("expires", -1.0))
	var scent_until: float = float(bag.get("corpse_scent_until", -1.0))
	var x: float = float(bag.get("x", NAN))
	var z: float = float(bag.get("z", NAN))
	return is_finite(expiry) and is_finite(scent_until) and is_finite(x) and 		is_finite(z) and now < expiry and now < scent_until


## Fixed-cell index: nearby infected search at most nine buckets.
static func buckets(bags: Dictionary, now: float) -> Dictionary:
	var result: Dictionary = {}
	if not is_finite(now):
		return result
	for bag in bags.values():
		if not (bag is Dictionary) or not active(bag, now):
			continue
		var cell := Vector2i(floori(float(bag["x"]) / RADIUS),
			floori(float(bag["z"]) / RADIUS))
		if not result.has(cell):
			result[cell] = []
		result[cell].append(bag)
	return result


## Closest corpse only, ties settled by server-generated bag ID.
static func closest(index: Dictionary, enemy_position: Vector3, now: float) -> Dictionary:
	if not enemy_position.is_finite() or not is_finite(now):
		return {}
	var here := Vector2(enemy_position.x, enemy_position.z)
	var cell := Vector2i(floori(here.x / RADIUS), floori(here.y / RADIUS))
	var chosen: Dictionary = {}
	var best: float = INF
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for bag in index.get(cell + Vector2i(dx, dz), []):
				if not active(bag, now):
					continue
				var point := Vector2(float(bag["x"]), float(bag["z"]))
				var distance_sq: float = here.distance_squared_to(point)
				if distance_sq > RADIUS * RADIUS:
					continue
				if chosen.is_empty() or distance_sq < best or (
						is_equal_approx(distance_sq, best) and int(bag["id"]) < int(chosen["id"])):
					chosen = bag
					best = distance_sq
	return chosen
