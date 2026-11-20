extends RefCounted
## Field campfires trade shelter for stealth at night. All cues are server-owned.
## A cell-based index keeps light lures cheap when many camps are active.

const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")
const REVEAL_RADIUS := 30.0
const LURE_RADIUS := 26.0


static func reveal_radius(fires: Dictionary, survivor: Vector3, now: float, night: bool) -> float:
	if not night or not is_finite(now) or not survivor.is_finite():
		return 0.0
	return REVEAL_RADIUS if FieldCampfire.has_warmth(fires, survivor, now) else 0.0


## Exclude expired or invalid fires even before the next world cleanup pass.
static func light_buckets(fires: Dictionary, now: float, night: bool) -> Dictionary:
	var buckets: Dictionary = {}
	if not night or not is_finite(now):
		return buckets
	for fire in fires.values():
		if not (fire is Dictionary) or not fire.has("id"):
			continue
		var expiry: float = float(fire.get("expires", -1.0))
		var x: float = float(fire.get("x", NAN))
		var z: float = float(fire.get("z", NAN))
		if not is_finite(expiry) or expiry <= now or not is_finite(x) or not is_finite(z):
			continue
		var cell := Vector2i(floori(x / LURE_RADIUS), floori(z / LURE_RADIUS))
		if not buckets.has(cell):
			buckets[cell] = []
		buckets[cell].append(fire)
	return buckets


## Only the same or neighboring grid cells could contain an audible light.
## Equal-distance results are deterministic by persistent world fire ID.
static func nearest_light(buckets: Dictionary, infected: Vector3) -> Dictionary:
	if not infected.is_finite():
		return {}
	var here := Vector2(infected.x, infected.z)
	var cell := Vector2i(floori(here.x / LURE_RADIUS), floori(here.y / LURE_RADIUS))
	var closest: Dictionary = {}
	var best_distance := LURE_RADIUS * LURE_RADIUS
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for fire in buckets.get(cell + Vector2i(dx, dz), []):
				var at := Vector2(float(fire["x"]), float(fire["z"]))
				var d: float = here.distance_squared_to(at)
				if d > best_distance:
					continue
				if closest.is_empty() or d < best_distance or (
						is_equal_approx(d, best_distance) and
						int(fire["id"]) < int(closest["id"])):
					closest = fire
					best_distance = d
	return closest
