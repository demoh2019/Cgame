extends RefCounted
## Dangerous-zone public supply drops. The server decides sites, tiers and rewards.
## No scene physics or client RPC is needed: drops use existing loot bags and snapshots.

const Defs = preload("res://scripts/shared/defs.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")

const INTERVAL_SECONDS := 300.0
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
		if not ZoneRisk.full_loot(zone) or world.is_safe(point.x, point.y) or world.is_water(point.x, point.y):
			continue
		var ground_normal: Vector3 = world.normal_at(point.x, point.y)
		if not ground_normal.is_finite() or ground_normal.y < 0.75:
			continue
		var elevation: float = world.height_at(point.x, point.y)
		if not is_finite(elevation):
			continue
		return {"x": point.x, "y": elevation, "z": point.y, "zone": zone}
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

## IDs are server-only and absent from client snapshots. Ordinary bags are unaffected.
static func living_guards(bag: Dictionary, infected: Dictionary) -> int:
	if not bool(bag.get("supply_drop", false)):
		return 0
	var remaining := 0
	for id in bag.get("supply_guard_ids", []):
		var guard = infected.get(int(id))
		if guard != null and guard.is_alive():
			remaining += 1
	return remaining


## Release is one-shot and only after the LAST real escort is defeated.
## The public cache remains available to any survivor; no killer owns it.
## The original escort count prevents unguarded caches from faking an event.
static func mark_cleared(bag: Dictionary, infected: Dictionary) -> bool:
	if not bool(bag.get("supply_drop", false)) or bool(bag.get("clear_announced", false)):
		return false
	var ids: Array = bag.get("supply_guard_ids", [])
	if ids.is_empty() or living_guards(bag, infected) != 0:
		return false
	bag["clear_announced"] = true
	return true


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
const GUARD_GRID_HALF := Vector2(12.0, 12.0)
const GUARD_GRID_SPACING := 6.0
const GUARD_GRID_SAMPLES := 25 # Bounded 5x5 fallthrough when all rings are blocked.



static func guard_types(zone: int) -> Array[String]:
	if zone == 2:
		return ["walker", "runner"]
	if zone == 3:
		return ["runner", "walker", "brute"]
	return []


## A context-relative 5x5 backup search. Never trusts client coordinates.
## Direction points AWAY from the closest finite survivor; ties use X/Z.
static func guard_grid_candidates(center: Vector2, survivors: Array[Vector3],
		prefer_native: bool = true) -> PackedVector2Array:
	var result := PackedVector2Array()
	if not center.is_finite():
		return result
	var facing := Vector2(0.0, 1.0)
	var nearest := INF
	var nearest_point := Vector2.INF
	for survivor in survivors:
		if not survivor.is_finite():
			continue
		var at := Vector2(survivor.x, survivor.z)
		var away := center - at
		var squared := away.length_squared()
		if squared > 0.000001 and is_finite(squared) and \
				(squared < nearest or (squared == nearest and \
				(at.x < nearest_point.x or (at.x == nearest_point.x and at.y < nearest_point.y)))):
			nearest = squared
			nearest_point = at
			facing = away.normalized()
	var native_grid := PackedVector3Array()
	if prefer_native and ClassDB.class_exists("EnvironmentQuery3D") \
			and ClassDB.class_has_method("EnvironmentQuery3D", "sample_oriented_grid"):
		native_grid = ClassDB.class_call_static("EnvironmentQuery3D", "sample_oriented_grid",
			Vector3(center.x, 0.0, center.y), Vector3(facing.x, 0.0, facing.y),
			GUARD_GRID_HALF, GUARD_GRID_SPACING, GUARD_GRID_SAMPLES)
	var generated := PackedVector2Array()
	if native_grid.size() == GUARD_GRID_SAMPLES:
		for sample in native_grid:
			generated.append(Vector2(sample.x, sample.z))
	else:
		var right := Vector2(facing.y, -facing.x)
		for z_index in 5:
			for x_index in 5:
				var local := Vector2(-GUARD_GRID_HALF.x + float(x_index) * GUARD_GRID_SPACING,
					-GUARD_GRID_HALF.y + float(z_index) * GUARD_GRID_SPACING)
				generated.append(center + right * local.x + facing * local.y)
	# Skip samples at/inside the cache; only genuinely peripheral guard sites.
	for sample in generated:
		if sample.is_finite() and sample.distance_to(center) >= float(GUARD_RADII[0]):
			result.append(sample)
	return result


## Reusable authoritative vetting for both ordinary concentric rings and
## context-facing fallback grid; never bypass the game's security boundary.
static func _guard_point_safe(world, point: Vector2, zone: int,
		survivors: Array[Vector3], infected: Dictionary,
		selected: Array[Dictionary]) -> bool:
	if not point.is_finite() or world.zone_at(point.x, point.y) != zone or \
			world.is_safe(point.x, point.y) or world.is_water(point.x, point.y):
		return false
	var ground_normal: Vector3 = world.normal_at(point.x, point.y)
	if not ground_normal.is_finite() or ground_normal.y < 0.75 or \
			not Movement._is_free(world, point):
		return false
	for survivor in survivors:
		if survivor.is_finite() and \
				point.distance_to(Vector2(survivor.x, survivor.z)) < MIN_SURVIVOR_DISTANCE:
			return false
	for enemy in infected.values():
		if enemy.is_alive() and point.distance_to(
				Vector2(enemy.position.x, enemy.position.z)) < MIN_INFECTED_DISTANCE:
			return false
	for prior in selected:
		if point.distance_to(Vector2(float(prior["x"]), float(prior["z"]))) < MIN_GUARD_SEPARATION:
			return false
	return true


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
			if _guard_point_safe(world, point, zone, survivors, infected, result):
				result.append({"x": point.x, "z": point.y, "kind": kinds[result.size()]})
				if result.size() >= desired:
					return result
	# Only when rings are exhausted, supplement with engine-oriented grid.
	# Every candidate goes through the SAME server-owned safety predicate.
	for point in guard_grid_candidates(center, survivors):
		if _guard_point_safe(world, point, zone, survivors, infected, result):
			result.append({"x": point.x, "z": point.y, "kind": kinds[result.size()]})
			if result.size() >= desired:
				return result
	return result
