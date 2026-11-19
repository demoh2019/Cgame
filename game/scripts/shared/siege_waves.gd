extends RefCounted
## Predictable, bounded server-driven infected attacks on defended survivors.
## No player RPC can create a wave or select a spawn position. Waves are an
## event during the live session; persistent building data is unchanged.

const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const Movement = preload("res://scripts/shared/movement.gd")

const CHECK_EVERY_TICKS := 20
const GLOBAL_COOLDOWN := 45.0
const WALL_COOLDOWN := 180.0
const MAX_ACTIVE_ZOMBIES := 90
const MAX_PER_WAVE := 5
const PLAYER_WALL_RANGE := 26.0
const MIN_PLAYER_SPAWN_DISTANCE := 10.0
const SPAWN_RADII := [15.0, 20.0, 24.0]
const SPAWN_ANGLES := 12


static func wave_size(tier: int) -> int:
	return clampi(1 + tier, 2, MAX_PER_WAVE)


static func eligible(wall: Dictionary, player_position: Vector3, world_time: float) -> bool:
	if not WorldCycle.is_night(world_time) or not player_position.is_finite():
		return false
	if Structures.tier_of(wall) < 1 or Structures.tier_of(wall) > Structures.MAX_TIER:
		return false
	var site := Vector2(float(wall["x"]), float(wall["z"]))
	if not site.is_finite() or site.length() < Structures.MIN_HUB_DISTANCE:
		return false
	return Structures.within_range(site, Vector2(player_position.x, player_position.z), PLAYER_WALL_RANGE)


## Defensive spawn search. Never materialize infected inside a survivor,
## structure, natural collider, protected hub or deep water.
static func spawn_sites(world, wall: Dictionary, survivor: Vector3, count: int,
		offset: int = 0) -> Array[Vector2]:
	var found: Array[Vector2] = []
	if count <= 0 or not survivor.is_finite():
		return found
	var target := Vector2(float(wall["x"]), float(wall["z"]))
	var player := Vector2(survivor.x, survivor.z)
	for ring in SPAWN_RADII:
		for index in SPAWN_ANGLES:
			if found.size() >= mini(count, MAX_PER_WAVE):
				return found
			var angle := TAU * float((index + offset) % SPAWN_ANGLES) / float(SPAWN_ANGLES)
			var point := target + Vector2.from_angle(angle) * ring
			if point.length() < Structures.MIN_HUB_DISTANCE:
				continue
			if player.distance_squared_to(point) < MIN_PLAYER_SPAWN_DISTANCE * MIN_PLAYER_SPAWN_DISTANCE:
				continue
			if world.is_water(point.x, point.y) or not Movement._is_free(world, point):
				continue
			var crowded := false
			for candidate in found:
				if point.distance_squared_to(candidate) < 16.0:
					crowded = true
					break
			if not crowded:
				found.append(point)
	return found
