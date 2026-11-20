extends RefCounted
## Ephemeral shared storm/cold cover; never a safe zone or permanent fortification.
const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")
const COST := {"cloth_1": 2, "fiber_1": 2, "plank_1": 1}
const DURATION := 240.0
const COVER_RADIUS := 3.5
const WEATHER_REDUCTION := 0.75
const MIN_SEPARATION := 4.0
const CANOPY_RADIUS := 0.75
const MAX_GLOBAL := 64
const MAX_PER_OWNER := 1
const PACK_RANGE := 3.2


static func valid_site(world, point: Vector2, origin: Vector2,
		shelters: Dictionary, campfires: Dictionary) -> String:
	var reason: String = FieldCampfire.valid_site(world, point, origin, campfires)
	if reason != "":
		return reason
	for shelter in shelters.values():
		var target := Vector2(float(shelter["x"]), float(shelter["z"]))
		if point.distance_squared_to(target) < MIN_SEPARATION * MIN_SEPARATION:
			return "blocked"
	for blocker in world.blockers_near(point.x, point.y, CANOPY_RADIUS + 1.0):
		var target := Vector2(float(blocker["x"]), float(blocker["z"]))
		if point.distance_to(target) < CANOPY_RADIUS + float(blocker["radius"]) + 0.15:
			return "blocked"
	return ""


static func covers(shelters: Dictionary, position: Vector3, now: float) -> bool:
	if not position.is_finite() or not is_finite(now):
		return false
	var here := Vector2(position.x, position.z)
	for shelter in shelters.values():
		var expiry: float = float(shelter.get("expires", -1.0))
		if not is_finite(expiry) or expiry <= now:
			continue
		var site := Vector2(float(shelter["x"]), float(shelter["z"]))
		if here.distance_squared_to(site) <= COVER_RADIUS * COVER_RADIUS:
			return true
	return false


static func exposure_severity(severity: float, covered: bool) -> float:
	if not is_finite(severity):
		return 0.0
	return clampf(severity, 0.0, 1.0) * (1.0 - WEATHER_REDUCTION if covered else 1.0)


static func visible(shelters: Dictionary, position: Vector3, now: float, radius: float) -> Array:
	var result: Array = []
	if not position.is_finite() or not is_finite(now) or not is_finite(radius) or radius < 0.0:
		return result
	var here := Vector2(position.x, position.z)
	for shelter in shelters.values():
		var remaining: float = float(shelter["expires"]) - now
		if remaining <= 0.0:
			continue
		var site := Vector2(float(shelter["x"]), float(shelter["z"]))
		if here.distance_squared_to(site) <= radius * radius:
			result.append({"id": int(shelter["id"]), "x": site.x,
				"y": float(shelter["y"]), "z": site.y, "remaining": remaining})
	return result
