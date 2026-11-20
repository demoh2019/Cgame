extends RefCounted
## Trade routes through red/black full-loot land attract finite infected waves.
## All prerequisites are checked from the real server-owned character, backpack
## and world position. One encounter per active route survives relogging.
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")
const NightHorde = preload("res://scripts/shared/night_horde.gd")

const CHECK_EVERY_TICKS := 20
const MAX_ACTIVE_INFECTED := 85
const MAX_ACTIVE_WAVES := 4
const LIFETIME_SECONDS := 190.0
const MIN_TRAVEL_METERS := 80.0
const ROUTE_PROGRESS := 0.35
const DESTINATION_CLEARANCE := 32.0


static func eligible(world, player_position: Vector3, route: Dictionary,
		carried_count: int, completed: bool, alive: bool) -> bool:
	if not alive or completed or carried_count < 1 or not player_position.is_finite():
		return false
	if route.is_empty():
		return false
	for key in ["src_x", "src_z", "dst_x", "dst_z", "distance", "cargo"]:
		if not route.has(key):
			return false
	var origin := Vector2(float(route["src_x"]), float(route["src_z"]))
	var destination := Vector2(float(route["dst_x"]), float(route["dst_z"]))
	var here := Vector2(player_position.x, player_position.z)
	var length: float = float(route["distance"])
	if not origin.is_finite() or not destination.is_finite() or not is_finite(length) \
			or length < MIN_TRAVEL_METERS:
		return false
	if not ZoneRisk.full_loot(world.zone_at(here.x, here.y)) or world.is_safe(here.x, here.y):
		return false
	return here.distance_to(origin) >= maxf(MIN_TRAVEL_METERS, length * ROUTE_PROGRESS) \
		and here.distance_to(destination) >= DESTINATION_CLEARANCE


## Reuse existing terrain-safe NightHorde placements, but never create the
## public horde trophy or another independent loot reward.
static func placement(world, origin: Vector3, survivors: Array[Vector3],
		infected: Dictionary, capacity: int, seed_angle: int) -> Array[Dictionary]:
	return NightHorde.sites(world, origin, survivors, infected,
		mini(capacity, 4), seed_angle)


static func available(active_waves: Array, infected: Dictionary) -> int:
	if active_waves.size() >= MAX_ACTIVE_WAVES:
		return 0
	return maxi(0, MAX_ACTIVE_INFECTED - infected.size())
