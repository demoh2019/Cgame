extends RefCounted
## Random world incidents that keep the map alive between the big timed events:
## a wandering horde drawn toward a survivor, a survivors' cache under guard, and a
## screamer with an escort. The server picks the moment, the place and every spawn;
## clients only hear about it (event "incident") and see the infected and the cache.

const INTERVAL_MIN := 90.0
const INTERVAL_MAX := 150.0
const RETRY_SECONDS := 20.0
const MAX_ACTIVE_INFECTED := 150 # Incidents never push the server past this many infected.
const MIN_DISTANCE := 40.0
const MAX_DISTANCE := 70.0
const KINDS := ["horde", "cache", "screamer"]


static func next_delay(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(INTERVAL_MIN, INTERVAL_MAX)


static func pick_kind(rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	if roll < 0.45:
		return "horde"
	if roll < 0.8:
		return "cache"
	return "screamer"


## A dry, walkable, non-safe spot 40-70 m from the survivor, or {} when none is found.
static func site_near(world, around: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	if not around.is_finite():
		return {}
	var origin := Vector2(around.x, around.z)
	for attempt in 12:
		var point := origin + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(MIN_DISTANCE, MAX_DISTANCE)
		if world.is_water(point.x, point.y) or world.is_safe(point.x, point.y):
			continue
		if world.normal_at(point.x, point.y).y < 0.75:
			continue
		return {"x": point.x, "z": point.y, "y": world.height_at(point.x, point.y),
			"zone": world.zone_at(point.x, point.y)}
	return {}


## Infected types for an incident in a zone. Deterministic for the given rng.
static func roster(kind: String, zone: int, rng: RandomNumberGenerator) -> Array:
	var result: Array = []
	match kind:
		"horde":
			for i in 5 + zone * 2 + rng.randi_range(0, 3):
				var roll := rng.randf()
				result.append("runner" if roll < 0.15 + 0.05 * zone else ("crawler" if roll < 0.55 else "walker"))
		"cache":
			for i in 2 + mini(zone, 2) + rng.randi_range(0, 1):
				result.append("sentinel" if zone >= 2 and i == 0 else ("brute" if zone >= 1 and i == 0 else "walker"))
		"screamer":
			result.append("howler")
			for i in 2 + mini(zone, 2):
				result.append("runner" if zone >= 1 else "walker")
	return result
