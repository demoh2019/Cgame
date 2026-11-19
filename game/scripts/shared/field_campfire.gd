extends RefCounted
## Short-lived warmth in the hostile world. Camps are neither shelters for
## persistence nor a substitute for permanent player-owned construction.

const Structures = preload("res://scripts/shared/structures.gd")
const COST := {"wood_1": 3, "stone_1": 1}
const REFUEL_COST := {"wood_1": 2}
const REFUEL_SECONDS := 120.0
const MAX_REMAINING_SECONDS := 600.0
const REFUEL_RANGE := 3.2
const DURATION := 300.0
const WARM_RADIUS := 5.0
const BUILD_RANGE := 4.0
const MIN_DISTANCE := 1.7
const MIN_SEPARATION := 2.5
const MAX_GLOBAL := 96
const MAX_PER_OWNER := 2
const CAMP_RADIUS := 0.45


static func valid_site(world, point: Vector2, from: Vector2, campfires: Dictionary) -> String:
	if not point.is_finite() or not from.is_finite():
		return "invalid_position"
	var distance := point.distance_to(from)
	if distance < MIN_DISTANCE or distance > BUILD_RANGE:
		return "out_of_range"
	if point.length() < Structures.MIN_HUB_DISTANCE:
		return "safe_zone"
	if world.is_water(point.x, point.y) or world.normal_at(point.x, point.y).y < Structures.MIN_SLOPE_NORMAL_Y:
		return "bad_terrain"
	for blocker in world.blockers_near(point.x, point.y, CAMP_RADIUS + 1.0):
		var other := Vector2(float(blocker["x"]), float(blocker["z"]))
		if point.distance_to(other) < CAMP_RADIUS + float(blocker["radius"]) + 0.15:
			return "blocked"
	for camp in campfires.values():
		var at := Vector2(float(camp["x"]), float(camp["z"]))
		if point.distance_to(at) < MIN_SEPARATION:
			return "blocked"
	return ""


## Any living survivor can contribute wood to a nearby shared campfire.
## Refusing when fewer than two minutes fit prevents charging for almost no heat.
static func refuel_reason(camp: Dictionary, position: Vector3, now: float) -> String:
	if camp.is_empty():
		return "no_fire"
	if not position.is_finite() or not is_finite(now):
		return "invalid_position"
	var expiry: float = float(camp.get("expires", -1.0))
	if not is_finite(expiry) or expiry <= now:
		return "expired"
	var point := Vector2(position.x, position.z)
	var site := Vector2(float(camp["x"]), float(camp["z"]))
	if point.distance_squared_to(site) > REFUEL_RANGE * REFUEL_RANGE:
		return "out_of_range"
	if expiry - now > MAX_REMAINING_SECONDS - REFUEL_SECONDS:
		return "full_duration"
	return ""


static func has_warmth(campfires: Dictionary, position: Vector3, now: float) -> bool:
	if not position.is_finite():
		return false
	var at := Vector2(position.x, position.z)
	for camp in campfires.values():
		if float(camp["expires"]) > now and at.distance_squared_to(
				Vector2(float(camp["x"]), float(camp["z"]))) <= WARM_RADIUS * WARM_RADIUS:
			return true
	return false


static func visible(campfires: Dictionary, position: Vector3, now: float, radius: float) -> Array:
	var result: Array = []
	if not position.is_finite():
		return result
	var at := Vector2(position.x, position.z)
	for camp in campfires.values():
		var target := Vector2(float(camp["x"]), float(camp["z"]))
		if float(camp["expires"]) > now and at.distance_squared_to(target) <= radius * radius:
			result.append({"id": int(camp["id"]), "x": target.x,
				"y": float(camp["y"]), "z": target.y,
				"remaining": maxf(0.0, float(camp["expires"]) - now)})
	return result
