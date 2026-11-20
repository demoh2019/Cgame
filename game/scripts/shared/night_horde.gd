extends RefCounted
## Limited night PvPvE horde for dangerous red/black regions.
## Server-only IDs and bounded, deterministic terrain-safe spawn search.
const Movement = preload("res://scripts/shared/movement.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")
const Defs = preload("res://scripts/shared/defs.gd")

const CHECK_EVERY_TICKS := 20
const START_DELAY := 480.0
const COOLDOWN_SECONDS := 780.0
const RETRY_SECONDS := 60.0
const MAX_DURATION := 300.0
const CACHE_DURATION := 240.0
const MAX_ACTIVE_INFECTED := 90
const MIN_PLAYER_SEPARATION := 12.0
const MAX_PLAYER_DISTANCE := 30.0
const MIN_INFECTED_SEPARATION := 3.5
const MIN_SPAWN_SEPARATION := 5.0
const RADII := [18.0, 22.0, 26.0]
const ANGLES := 16


static func kinds(zone: int) -> Array[String]:
	if zone == 2:
		return ["runner", "walker", "runner"]
	if zone == 3:
		return ["runner", "brute", "spitter", "runner"]
	return []


static func sites(world, origin: Vector3, survivors: Array[Vector3],
		infected: Dictionary, capacity: int, offset: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not origin.is_finite() or capacity <= 0:
		return result
	var center := Vector2(origin.x, origin.z)
	var zone: int = world.zone_at(center.x, center.y)
	if not ZoneRisk.full_loot(zone) or world.is_safe(center.x, center.y):
		return result
	var expected: Array[String] = kinds(zone)
	var target: int = mini(mini(expected.size(), capacity), MAX_ACTIVE_INFECTED)
	if target <= 0:
		return result
	for radius in RADII:
		for angle_index in ANGLES:
			var angle: float = TAU * float(posmod(angle_index + offset, ANGLES)) / float(ANGLES)
			var point := center + Vector2.from_angle(angle) * float(radius)
			if point.distance_to(center) > MAX_PLAYER_DISTANCE or \
					world.zone_at(point.x, point.y) != zone or \
					world.is_safe(point.x, point.y) or world.is_water(point.x, point.y) or \
					world.normal_at(point.x, point.y).y < 0.75 or \
					not Movement._is_free(world, point):
				continue
			var clear := true
			for survivor in survivors:
				if survivor.is_finite() and point.distance_to(
						Vector2(survivor.x, survivor.z)) < MIN_PLAYER_SEPARATION:
					clear = false
					break
			if not clear:
				continue
			for enemy in infected.values():
				if enemy.is_alive() and enemy.position.is_finite() and \
						point.distance_to(Vector2(enemy.position.x, enemy.position.z)) < MIN_INFECTED_SEPARATION:
					clear = false
					break
			if not clear:
				continue
			for prior in result:
				if point.distance_to(Vector2(float(prior["x"]), float(prior["z"]))) < MIN_SPAWN_SEPARATION:
					clear = false
					break
			if clear:
				result.append({"x": point.x, "z": point.y, "kind": expected[result.size()]})
				if result.size() >= target:
					return result
	return result


## A missing/despawned enemy is NOT a legitimate combat victory.
static func fully_defeated(ids: Array, infected: Dictionary) -> bool:
	if ids.is_empty():
		return false
	for id in ids:
		if not infected.has(int(id)) or infected[int(id)].is_alive():
			return false
	return true


static func loot(zone: int) -> Dictionary:
	if zone == 3:
		return {"infected_core": 2, "bar_4": 3, "silver": 170}
	if zone == 2:
		return {"infected_core": 1, "bar_3": 3, "silver": 110}
	return {}
