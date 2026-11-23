extends RefCounted
## Short-lived warmth in the hostile world. Camps are neither shelters for
## persistence nor a substitute for permanent player-owned construction.

const Structures = preload("res://scripts/shared/structures.gd")
const COST := {"wood_1": 3, "stone_1": 1}
const REFUEL_COST := {"wood_1": 2}
const REFUEL_SECONDS := 120.0
const MAX_REMAINING_SECONDS := 600.0
const REFUEL_RANGE := 3.2
const REFUEL_HEIGHT := 2.5
const DURATION := 300.0
const WARM_RADIUS := 5.0
const WARM_HEIGHT := 3.5
const BUILD_RANGE := 4.0
const MIN_DISTANCE := 1.7
const MIN_SEPARATION := 2.5
const MAX_GLOBAL := 96
const MAX_PER_OWNER := 2
const CAMP_RADIUS := 0.45
const STORM_BURN_MULTIPLIER := 2.0


## Ordinary time already burns one second of fuel per server second.
## The storm penalty only applies to the extra second; invalid input is safe.
static func storm_extra_fuel(delta: float, weather: Dictionary) -> float:
	if not is_finite(delta) or delta <= 0.0:
		return 0.0
	if str(weather.get("condition", "")) != "storm" or bool(weather.get("sheltered", false)):
		return 0.0
	return delta * (STORM_BURN_MULTIPLIER - 1.0)


static func valid_site(world, point: Vector2, from: Vector2, campfires: Dictionary) -> String:
	if not point.is_finite() or not from.is_finite():
		return "invalid_position"
	var distance := point.distance_to(from)
	if distance < MIN_DISTANCE or distance > BUILD_RANGE:
		return "out_of_range"
	if point.length() < Structures.MIN_HUB_DISTANCE:
		return "safe_zone"
	var terrain_normal: Vector3 = world.normal_at(point.x, point.y)
	if world.is_water(point.x, point.y) or not terrain_normal.is_finite() or terrain_normal.y < Structures.MIN_SLOPE_NORMAL_Y:
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
	var site := Vector2(float(camp.get("x", NAN)), float(camp.get("z", NAN)))
	var camp_y: float = float(camp.get("y", NAN))
	# A corrupted location must never bypass the distance check or
	# charge wood for a remote refuel.
	if not site.is_finite() or not is_finite(camp_y):
		return "invalid_position"
	if absf(position.y - camp_y) > REFUEL_HEIGHT or \
			point.distance_squared_to(site) > REFUEL_RANGE * REFUEL_RANGE:
		return "out_of_range"
	if expiry - now > MAX_REMAINING_SECONDS - REFUEL_SECONDS:
		return "full_duration"
	return ""


static func has_warmth(campfires: Dictionary, position: Vector3, now: float) -> bool:
	if not position.is_finite() or not is_finite(now):
		return false
	var at := Vector2(position.x, position.z)
	for camp in campfires.values():
		var expiry: float = float(camp.get("expires", NAN))
		if not is_finite(expiry) or expiry <= now:
			continue
		var site := Vector2(float(camp.get("x", NAN)), float(camp.get("z", NAN)))
		var camp_y: float = float(camp.get("y", NAN))
		if site.is_finite() and is_finite(camp_y) and \
				absf(position.y - camp_y) <= WARM_HEIGHT and \
				at.distance_squared_to(site) <= WARM_RADIUS * WARM_RADIUS:
			return true
	return false


static func visible(campfires: Dictionary, position: Vector3, now: float, radius: float) -> Array:
	var result: Array = []
	if not position.is_finite() or not is_finite(now) or not is_finite(radius) or radius < 0.0:
		return result
	var radius_squared: float = radius * radius
	if not is_finite(radius_squared):
		return result
	var at := Vector2(position.x, position.z)
	for camp in campfires.values():
		var expiry: float = float(camp.get("expires", NAN))
		var target := Vector2(float(camp.get("x", NAN)), float(camp.get("z", NAN)))
		var height: float = float(camp.get("y", NAN))
		if not is_finite(expiry) or expiry <= now or not target.is_finite() or not is_finite(height):
			continue
		if at.distance_squared_to(target) <= radius_squared:
			var alarm_until: float = float(camp.get("alarm_until", now))
			var stormproof_until: float = float(camp.get("stormproof_until", 0.0))
			result.append({"id": int(camp["id"]), "x": target.x,
				"y": height, "z": target.y,
				"remaining": expiry - now,
				"alarm_seconds": maxf(0.0, minf(alarm_until, expiry) - now) if is_finite(alarm_until) else 0.0,
				"stormproof_seconds": maxf(0.0, stormproof_until - now) if is_finite(stormproof_until) else 0.0})
	return result
