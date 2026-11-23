extends RefCounted
## Field-built one-use snares stop roaming infected, not players or raid bosses.
## Site, cost, lifetime and trigger are exclusively server-authoritative.

const ITEM_ID := "infected_snare"
const DURATION := 150.0
const ROOT_SECONDS := 3.0
const ELITE_ROOT_SECONDS := 1.5
const TRIGGER_RADIUS := 1.35
const BUILD_RANGE := 4.0
const MIN_RANGE := 1.5
const MIN_SEPARATION := 2.2
const MAX_GLOBAL := 64
const MAX_PER_OWNER := 3


static func valid_site(world, site: Vector2, origin: Vector2, existing: Dictionary) -> String:
	if not site.is_finite() or not origin.is_finite():
		return "invalid_position"
	var distance: float = site.distance_to(origin)
	if distance < MIN_RANGE or distance > BUILD_RANGE:
		return "out_of_range"
	if world.is_safe(site.x, site.y):
		return "safe_zone"
	if world.is_water(site.x, site.y) or world.normal_at(site.x, site.y).y < 0.7:
		return "bad_terrain"
	for obstacle in world.blockers_near(site.x, site.y, TRIGGER_RADIUS + 0.7):
		var center := Vector2(float(obstacle["x"]), float(obstacle["z"]))
		if site.distance_to(center) < TRIGGER_RADIUS + float(obstacle["radius"]) + 0.1:
			return "blocked"
	for trap in existing.values():
		var other := Vector2(float(trap["x"]), float(trap["z"]))
		if site.distance_to(other) < MIN_SEPARATION:
			return "blocked"
	return ""


static func catches(trap: Dictionary, infected, now: float) -> bool:
	if infected == null or not infected.is_alive() or infected.raid_boss or \
			not is_finite(now) or now < 0.0 or not infected.position.is_finite():
		return false
	var expiry_value: Variant = trap.get("expires", null)
	if not (expiry_value is int or expiry_value is float) or \
			not (trap.get("x", null) is int or trap.get("x", null) is float) or \
			not (trap.get("z", null) is int or trap.get("z", null) is float):
		return false
	var expiry: float = float(expiry_value)
	var center := Vector2(float(trap["x"]), float(trap["z"]))
	if not is_finite(expiry) or expiry <= now or not center.is_finite():
		return false
	var position := Vector2(infected.position.x, infected.position.z)
	var distance_squared: float = position.distance_squared_to(center)
	return is_finite(distance_squared) and distance_squared <= TRIGGER_RADIUS * TRIGGER_RADIUS


static func root_duration(infected) -> float:
	return ELITE_ROOT_SECONDS if infected.elite else ROOT_SECONDS


static func visible(traps: Dictionary, position: Vector3, now: float, radius: float) -> Array:
	var output: Array = []
	if not position.is_finite() or not is_finite(now) or now < 0.0 or \
			not is_finite(radius) or radius <= 0.0:
		return output
	var here := Vector2(position.x, position.z)
	var radius_squared: float = radius * radius
	if not is_finite(radius_squared):
		return output
	for value in traps.values():
		if not (value is Dictionary):
			continue
		var trap: Dictionary = value
		if not (trap.get("id", null) is int) or \
				not (trap.get("expires", null) is float or trap.get("expires", null) is int) or \
				not (trap.get("x", null) is float or trap.get("x", null) is int) or \
				not (trap.get("y", null) is float or trap.get("y", null) is int) or \
				not (trap.get("z", null) is float or trap.get("z", null) is int):
			continue
		var expiry: float = float(trap["expires"])
		var at := Vector2(float(trap["x"]), float(trap["z"]))
		var altitude: float = float(trap["y"])
		if not is_finite(expiry) or expiry <= now or not at.is_finite() or \
				not is_finite(altitude):
			continue
		var distance_squared: float = here.distance_squared_to(at)
		if is_finite(distance_squared) and distance_squared <= radius_squared:
			# Never send owner account, server expiry, or trigger bookkeeping.
			output.append({"id": int(trap["id"]), "x": at.x,
				"y": altitude, "z": at.y,
				"remaining": expiry - now})
	return output
