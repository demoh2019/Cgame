extends RefCounted
## Dangerous-zone public supply drops. The server decides sites, tiers and rewards.
## No scene physics or client RPC is needed: drops use existing loot bags and snapshots.

const Defs = preload("res://scripts/shared/defs.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")

const INTERVAL_SECONDS := 600.0
const RETRY_SECONDS := 60.0
const LIFETIME_SECONDS := 420.0
const MIN_DISTANCE := 32.0
const MAX_DISTANCE := 54.0
const SITE_ATTEMPTS := 24


## Pick dry, walkable ground close enough for interest-management visibility.
## Returns an empty dictionary rather than dropping loot in water or protected zones.
static func site_near(world, player_position: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	if not is_finite(player_position.x) or not is_finite(player_position.z):
		return {}
	if not ZoneRisk.full_loot(world.zone_at(player_position.x, player_position.z)):
		return {}
	var origin := Vector2(player_position.x, player_position.z)
	for attempt in SITE_ATTEMPTS:
		var direction := Vector2.from_angle(rng.randf_range(0.0, TAU))
		var point := origin + direction * rng.randf_range(MIN_DISTANCE, MAX_DISTANCE)
		var zone: int = world.zone_at(point.x, point.y)
		if not ZoneRisk.full_loot(zone) or world.is_water(point.x, point.y):
			continue
		if world.normal_at(point.x, point.y).y < 0.75:
			continue
		return {"x": point.x, "y": world.height_at(point.x, point.y),
			"z": point.y, "zone": zone}
	return {}


## Bounded, known inventory IDs; there are no client-supplied reward amounts.
static func loot_for_zone(zone: int, rng: RandomNumberGenerator) -> Dictionary:
	var tier: int = clampi(zone + 1, 3, Defs.MAX_TIER)
	return {
		"silver": 40 * tier,
		"bar_%d" % tier: rng.randi_range(3, 5),
		"cloth_%d" % tier: rng.randi_range(3, 5),
		"bandage": 2,
		"ammo_9mm": rng.randi_range(6, 12),
	}
