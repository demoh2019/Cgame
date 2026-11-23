extends RefCounted
## One step of player movement. The server runs it to decide where a player is, and the client runs
## the very same function to predict its own player, so the two agree except when something the
## client could not know (another player is not an obstacle here) intervenes.

const Defs = preload("res://scripts/shared/defs.gd")
const StealthStance = preload("res://scripts/shared/stealth_stance.gd")
const Mounts = preload("res://scripts/shared/mounts.gd")
const BikeTerrain = preload("res://scripts/shared/bike_terrain.gd")
const BikeIntegrity = preload("res://scripts/shared/bike_integrity.gd")
const RoadTravel = preload("res://scripts/shared/road_travel.gd")
const StormMud = preload("res://scripts/shared/storm_mud.gd")
const WadingTravel = preload("res://scripts/shared/wading_travel.gd")
const Swimming = preload("res://scripts/shared/swimming.gd")

const MAX_DELTA := 0.1 # A longer step is clamped, so a lag spike cannot teleport a player.
const COLLISION_STEP := 0.2 # Sample every 20 cm to avoid stepping over narrow obstacles.


## `input` has "x", "z" (a move direction, any length up to 1) and "sprint". Returns the new position
## (y follows the ground). Water that is too deep and solid objects stop the player, and sliding
## along them keeps the movement smooth.
static func step(world, position: Vector3, input: Dictionary, delta: float) -> Vector3:
	var result: Vector3 = _step_on_foot(world, position, input, delta)
	# Survivors on foot float in deep water; crouching dives. Bikes never enter it.
	if not bool(input.get("mounted", false)) and result.is_finite() and Swimming.is_swimming(world, result.x, result.z):
		if bool(input.get("raft", false)):
			result.y = Defs.WATER_LEVEL - 0.15 # Sitting on the raft, on the surface.
		else:
			result.y = Swimming.body_y(world, result.x, result.z, bool(input.get("crouch", false)))
	return result


static func _step_on_foot(world, position: Vector3, input: Dictionary, delta: float) -> Vector3:
	if not is_finite(delta):
		return Vector3(position.x, world.height_at(position.x, position.z), position.z)
	delta = clampf(delta, 0.0, MAX_DELTA)
	var direction := Vector2(float(input.get("x", 0.0)), float(input.get("z", 0.0)))
	if not direction.is_finite():
		return Vector3(position.x, world.height_at(position.x, position.z), position.z)
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	if direction == Vector2.ZERO or delta == 0.0:
		return Vector3(position.x, world.height_at(position.x, position.z), position.z)
	# The server supplies this from its authoritative inventory, never from a network value.
	# With no factor (legacy/test inputs), movement stays unchanged.
	var cargo_raw := float(input.get("cargo_factor", 1.0))
	var injury_raw := float(input.get("injury_factor", 1.0))
	if not is_finite(cargo_raw):
		cargo_raw = 1.0
	if not is_finite(injury_raw):
		injury_raw = 1.0
	var factor := clampf(cargo_raw, Defs.CARRY_MIN_SPEED_FACTOR, 1.0)
	var injury_factor := clampf(injury_raw, Defs.FRACTURE_SPEED_FACTOR, 1.0)
	var crouching := bool(input.get("crouch", false))
	# This flag is constructed on the server from a physically owned bike.
	var bike_condition: float = float(input.get("bike_integrity", BikeIntegrity.MAX_INTEGRITY))
	var mounted := bool(input.get("mounted", false)) and not crouching and factor >= 0.9999 and injury_factor >= 0.9999 and BikeIntegrity.can_ride(bike_condition)
	var sprint := bool(input.get("sprint", false)) and not mounted and not crouching and factor >= 0.9999 and injury_factor >= 0.9999 and WadingTravel.can_sprint(world, position)
	# Skill bonus to movement speed: the server supplies it from the character's skills, the client
	# from the snapshot, so prediction matches. Capped so a forged input cannot run away.
	var raw_bonus := float(input.get("speed_bonus", 0.0))
	var bonus := clampf(raw_bonus, 0.0, 0.5) if is_finite(raw_bonus) else 0.0
	var base_speed: float = (Defs.WALK_SPEED * Mounts.SPEED_FACTOR
		if mounted else (Defs.SPRINT_SPEED if sprint else Defs.WALK_SPEED))
	var speed := base_speed * factor * injury_factor * (1.0 + bonus)
	if not mounted and Swimming.is_swimming(world, position.x, position.z) and bool(input.get("raft", false)):
		# Paddling a raft (carried, server-checked): fast across the surface; sprint pulls harder.
		var paddle: float = Defs.WALK_SPEED * (2.1 if bool(input.get("sprint", false)) else 1.6) * factor * injury_factor
		return move(world, position, direction, paddle, delta, true)
	if not mounted and Swimming.is_swimming(world, position.x, position.z):
		# Swimming: no sprint, roads or mud; diving is slower still.
		var swim_speed: float = Defs.WALK_SPEED * factor * injury_factor * (1.0 + bonus) * Swimming.speed_factor(crouching)
		return move(world, position, direction, swim_speed, delta, true)
	if mounted:
		# Surface, uphill drag and limited downhill boost are deterministic for both peers.
		speed *= BikeTerrain.speed_factor(world, position, direction,
			float(input.get("tire_grip_seconds", 0.0)))
		speed *= BikeIntegrity.speed_factor(bike_condition)
	else:
		# Genuine road speed for walking and sprinting, but not crouched stealth.
		speed *= RoadTravel.foot_factor(world, position, crouching)
	# Existing test inputs without a replicated weather clock remain unchanged.
	# Server derives this clock itself; clients predict from received time.
	var weather_time: float = float(input.get("weather_time", NAN))
	if is_finite(weather_time):
		speed *= StormMud.factor(world, position, weather_time, mounted)
	speed *= WadingTravel.factor(world, position, mounted)
	speed *= StealthStance.speed_factor(crouching)
	return move(world, position, direction, speed, delta, not mounted)


## Moves along `direction` (unit or shorter) at `speed` meters per second. Shared by players and zombies.
static func move(world, position: Vector3, direction: Vector2, speed: float, delta: float, allow_swim: bool = false) -> Vector3:
	if not is_finite(delta) or not is_finite(speed) or not direction.is_finite() or speed <= 0.0:
		return Vector3(position.x, world.height_at(position.x, position.z), position.z)
	delta = clampf(delta, 0.0, MAX_DELTA)
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	var displacement: Vector2 = direction * speed * delta
	if not displacement.is_finite():
		return Vector3(position.x, world.height_at(position.x, position.z), position.z)
	# Endpoint-only tests let a fast-moving character tunnel through a thin prop or wall.
	# Server and client prediction use identical small steps, with the same slide policy.
	var segments: int = maxi(1, ceili(displacement.length() / COLLISION_STEP))
	var increment: Vector2 = displacement / float(segments)
	var point := Vector2(position.x, position.z)
	for _i in segments:
		var target: Vector2 = point + increment
		var candidates: Array[Vector2] = [target, Vector2(target.x, point.y), Vector2(point.x, target.y)]
		var accepted := false
		for candidate in candidates:
			if _is_free(world, candidate, allow_swim):
				point = candidate
				accepted = true
				break
		if not accepted:
			break
	return Vector3(point.x, world.height_at(point.x, point.y), point.y)


## Short, server-authored physical impulses use many collision-checked
## substeps. A single large move() call could leap across a narrow blocker.
## Reuse the same water, solid-obstacle and wall-slide rules as locomotion.
## This primitive does not apply any damage or authorize PvP displacement.
static func sweep_displacement(world, position: Vector3, displacement: Vector2,
		max_meters: float = 3.0) -> Vector3:
	if not position.is_finite() or not displacement.is_finite() or not is_finite(max_meters):
		return position
	if max_meters <= 0.0 or not is_finite(displacement.length_squared()):
		return position
	var meters: float = minf(displacement.length(), minf(max_meters, 3.0))
	if meters < 0.001:
		return position
	var direction: Vector2 = displacement.normalized()
	var result: Vector3 = position
	var remaining: float = meters
	# 0.2 m segments prevent tunnelling through world blockers or shores.
	for i in ceili(meters / 0.2):
		var step_meters: float = minf(0.2, remaining)
		if step_meters <= 0.0001:
			break
		var next: Vector3 = move(world, result, direction,
			step_meters / MAX_DELTA, MAX_DELTA)
		if Vector2(next.x - result.x, next.z - result.z).length_squared() < 0.000001:
			break
		result = next
		remaining -= step_meters
	return result


## The server never loads decorative meshes. Its seeded structures carry their
## footprint and orientation; use that for buildings and walls, rather than a
## circle that leaves the corners of large models walkable.
static func overlaps_blocker(point: Vector2, blocker: Dictionary) -> bool:
	var offset := point - Vector2(float(blocker["x"]), float(blocker["z"]))
	var kind: String = str(blocker.get("kind", ""))
	var scale: float = float(blocker.get("scale", 0.0))
	if scale > 0.0 and is_finite(scale) and (kind == "building" or kind == "wall"):
		var yaw: float = float(blocker.get("yaw", 0.0))
		if is_finite(yaw):
			# Inverse of the MeshInstance's Basis(Vector3.UP, yaw) in XZ.
			var local := Vector2(
				cos(yaw) * offset.x - sin(yaw) * offset.y,
				sin(yaw) * offset.x + cos(yaw) * offset.y)
			# Catalog houses are fitted to a 7 m footprint at scale 6;
			# wall segments are 3.8 m long at scale 3.
			var half: Vector2 = (Vector2.ONE * scale * (7.0 / 12.0)
				if kind == "building" else Vector2(scale * (3.8 / 6.0), scale * 0.11))
			var outside := Vector2(maxf(absf(local.x) - half.x, 0.0),
				maxf(absf(local.y) - half.y, 0.0))
			return outside.length_squared() < Defs.PLAYER_RADIUS * Defs.PLAYER_RADIUS
	# Trees, rock piles, crates and other props keep their circular collision.
	var combined: float = Defs.PLAYER_RADIUS + float(blocker["radius"])
	return offset.length_squared() < combined * combined


static func _is_free(world, point: Vector2, allow_swim: bool = false) -> bool:
	# Wading is allowed until the water is deeper than a meter; beyond that only swimmers.
	if not allow_swim and world.height_at(point.x, point.y) < Defs.WATER_LEVEL - 1.0:
		return false
	for blocker in world.blockers_near(point.x, point.y, Defs.PLAYER_RADIUS + 1.0):
		if overlaps_blocker(point, blocker):
			return false
	return true
