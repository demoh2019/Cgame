extends RefCounted
## Craftable thrown noise lures for stealthy survivor expeditions.
## Server-owned positions, costs and expiry; no fake player aggro or damage.

const ITEM_ID := "noise_decoy"
const THROW_DISTANCE := 8.0
const HEARING_RADIUS := 23.0
const DURATION := 8.0
const COOLDOWN := 3.0
const MAX_ACTIVE := 48
const MAX_PER_OWNER := 2
const MAX_COORD := 20000.0


## Returns a validated landing site. A requested direction is NOT an
## arbitrary client destination; the server derives all world coordinates.
static func landing(world, origin: Vector3, direction: Vector2) -> Dictionary:
	if not origin.is_finite() or not direction.is_finite():
		return {}
	# A finite vector may still overflow when squared; reject that case
	# before normalization. Safe-hub survivors cannot throw danger away
	# from protected ground into an outside combat zone.
	var squared: float = direction.length_squared()
	if not is_finite(squared) or squared < 0.0001:
		return {}
	if world.is_safe(origin.x, origin.z):
		return {}
	var heading: Vector2 = direction.normalized()
	var start := Vector2(origin.x, origin.z)
	var target := start + heading * THROW_DISTANCE
	if absf(target.x) > MAX_COORD or absf(target.y) > MAX_COORD:
		return {}
	if world.is_safe(target.x, target.y) or world.is_water(target.x, target.y):
		return {}
	if world.normal_at(target.x, target.y).y < 0.7:
		return {}
	# Sample the physical flight path so a client cannot throw through trees,
	# rock pillars or barricades to distract enemies on the far side.
	for step in range(1, 9):
		var point: Vector2 = start.lerp(target, float(step) / 8.0)
		for blocker in world.blockers_near(point.x, point.y, 0.35):
			if point.distance_to(Vector2(float(blocker["x"]), float(blocker["z"]))) < (
					float(blocker["radius"]) + 0.3):
				return {}
	return {"x": target.x, "y": world.height_at(target.x, target.y), "z": target.y}


static func is_audible(decoy: Dictionary, position: Vector3, now: float) -> bool:
	if not position.is_finite() or not is_finite(now):
		return false
	if float(decoy.get("expires", -1.0)) <= now:
		return false
	var offset := Vector2(position.x - float(decoy["x"]),
			position.z - float(decoy["z"]))
	return offset.length_squared() <= HEARING_RADIUS * HEARING_RADIUS


static func visible_state(decoy: Dictionary, now: float) -> Dictionary:
	return {"id": int(decoy["id"]),
		"x": float(decoy["x"]), "y": float(decoy["y"]), "z": float(decoy["z"]),
		"remaining": clampf(float(decoy["expires"]) - now, 0.0, DURATION)}



## Grid size equals hearing radius: any audible lure is in the same or
## an immediately adjacent cell. Build once per scheduled AI hearing pass.
## Avoid comparing every infected against every planted lure.
static func sound_buckets(decoys: Dictionary, now: float) -> Dictionary:
	var buckets: Dictionary = {}
	if not is_finite(now):
		return buckets
	for lure in decoys.values():
		if not (lure is Dictionary) or not lure.has("id"):
			continue
		var expiry: float = float(lure.get("expires", -1.0))
		var x: float = float(lure.get("x", NAN))
		var z: float = float(lure.get("z", NAN))
		if not is_finite(expiry) or expiry <= now or not is_finite(x) or not is_finite(z):
			continue
		var cell := Vector2i(floori(x / HEARING_RADIUS), floori(z / HEARING_RADIUS))
		if not buckets.has(cell):
			buckets[cell] = []
		buckets[cell].append(lure)
	return buckets


## Return the closest audible active lure, tie-breaking by stable world ID.
## No player IDs, account data or client-supplied detection distances involved.
static func closest_audible(buckets: Dictionary, position: Vector3, now: float) -> Dictionary:
	if not position.is_finite() or not is_finite(now):
		return {}
	var here := Vector2(position.x, position.z)
	var cell := Vector2i(floori(here.x / HEARING_RADIUS), floori(here.y / HEARING_RADIUS))
	var closest: Dictionary = {}
	var best_distance := INF
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for lure in buckets.get(cell + Vector2i(dx, dz), []):
				if not is_audible(lure, position, now):
					continue
				var point := Vector2(float(lure["x"]), float(lure["z"]))
				var distance_squared: float = here.distance_squared_to(point)
				if closest.is_empty() or distance_squared < best_distance or (
						is_equal_approx(distance_squared, best_distance) and
						int(lure["id"]) < int(closest["id"])):
					closest = lure
					best_distance = distance_squared
	return closest
