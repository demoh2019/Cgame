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


# Each crate is a small PvE encounter as well as a public PvP objective.
# Escorts are ordinary session zombies: no extra private rewards and no respawn.
const Movement = preload("res://scripts/shared/movement.gd")
const MAX_GUARDS := 3
const MAX_ACTIVE_INFECTED := 90
const MIN_SURVIVOR_DISTANCE := 12.0
const MIN_INFECTED_DISTANCE := 3.5
const MIN_GUARD_SEPARATION := 5.0
const GUARD_RADII := [8.0, 11.0, 14.0]
const GUARD_ANGLES := 16


static func guard_types(zone: int) -> Array[String]:
	if zone == 2:
		return ["walker", "runner"]
	if zone == 3:
		return ["runner", "walker", "brute"]
	return []


## Validate positions against server-owned player/zombie locations and collisions.
## Bad terrain or a nearby survivor reduces guards rather than spawning on top
## of somebody. The bounded angular search is deterministic for replay/tests.
static func guard_sites(world, site: Dictionary, survivors: Array[Vector3],
		infected: Dictionary, capacity: int, angle_offset: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if capacity <= 0:
		return result
	var x: float = float(site.get("x", NAN))
	var z: float = float(site.get("z", NAN))
	if not is_finite(x) or not is_finite(z):
		return result
	var center := Vector2(x, z)
	var zone: int = world.zone_at(x, z)
	if int(site.get("zone", -1)) != zone or not ZoneRisk.full_loot(zone) or \
			world.is_safe(x, z) or world.is_water(x, z):
		return result
	var kinds: Array[String] = guard_types(zone)
	var desired: int = mini(mini(capacity, MAX_GUARDS), kinds.size())
	for radius in GUARD_RADII:
		for index in GUARD_ANGLES:
			var angle: float = TAU * float(posmod(index + angle_offset, GUARD_ANGLES)) / float(GUARD_ANGLES)
			var point: Vector2 = center + Vector2.from_angle(angle) * float(radius)
			if world.zone_at(point.x, point.y) != zone or \
					world.is_safe(point.x, point.y) or world.is_water(point.x, point.y) or \
					world.normal_at(point.x, point.y).y < 0.75 or \
					not Movement._is_free(world, point):
				continue
			var clear := true
			for survivor in survivors:
				if survivor.is_finite() and point.distance_to(Vector2(survivor.x, survivor.z)) < MIN_SURVIVOR_DISTANCE:
					clear = false
					break
			if not clear:
				continue
			for enemy in infected.values():
				if enemy.is_alive() and point.distance_to(
						Vector2(enemy.position.x, enemy.position.z)) < MIN_INFECTED_DISTANCE:
					clear = false
					break
			if not clear:
				continue
			for prior in result:
				if point.distance_to(Vector2(float(prior["x"]), float(prior["z"]))) < MIN_GUARD_SEPARATION:
					clear = false
					break
			if clear:
				result.append({"x": point.x, "z": point.y, "kind": kinds[result.size()]})
				if result.size() >= desired:
					return result
	return result
