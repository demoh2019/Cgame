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
	if infected == null or not infected.is_alive() or infected.raid_boss:
		return false
	if not is_finite(now) or float(trap.get("expires", -1.0)) <= now:
		return false
	if not infected.position.is_finite():
		return false
	var center := Vector2(float(trap["x"]), float(trap["z"]))
	var position := Vector2(infected.position.x, infected.position.z)
	return position.distance_squared_to(center) <= TRIGGER_RADIUS * TRIGGER_RADIUS


static func root_duration(infected) -> float:
	return ELITE_ROOT_SECONDS if infected.elite else ROOT_SECONDS


static func visible(traps: Dictionary, position: Vector3, now: float, radius: float) -> Array:
	var output: Array = []
	if not position.is_finite():
		return output
	var here := Vector2(position.x, position.z)
	for trap in traps.values():
		var at := Vector2(float(trap["x"]), float(trap["z"]))
		if float(trap["expires"]) > now and here.distance_squared_to(at) <= radius * radius:
			# Never send owner account, server expiry, or trigger bookkeeping.
			output.append({"id": int(trap["id"]), "x": float(trap["x"]),
				"y": float(trap["y"]), "z": float(trap["z"]),
				"remaining": maxf(0.0, float(trap["expires"]) - now)})
	return output
