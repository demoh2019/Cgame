extends RefCounted
## One step of player movement. The server runs it to decide where a player is, and the client runs
## the very same function to predict its own player, so the two agree except when something the
## client could not know (another player is not an obstacle here) intervenes.

const Defs = preload("res://scripts/shared/defs.gd")
const StealthStance = preload("res://scripts/shared/stealth_stance.gd")
const Mounts = preload("res://scripts/shared/mounts.gd")
const BikeTerrain = preload("res://scripts/shared/bike_terrain.gd")

const MAX_DELTA := 0.1 # A longer step is clamped, so a lag spike cannot teleport a player.


## `input` has "x", "z" (a move direction, any length up to 1) and "sprint". Returns the new position
## (y follows the ground). Water that is too deep and solid objects stop the player, and sliding
## along them keeps the movement smooth.
static func step(world, position: Vector3, input: Dictionary, delta: float) -> Vector3:
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
	var mounted := bool(input.get("mounted", false)) and not crouching and factor >= 0.9999 and injury_factor >= 0.9999
	var sprint := bool(input.get("sprint", false)) and not mounted and not crouching and factor >= 0.9999 and injury_factor >= 0.9999
	# Skill bonus to movement speed: the server supplies it from the character's skills, the client
	# from the snapshot, so prediction matches. Capped so a forged input cannot run away.
	var raw_bonus := float(input.get("speed_bonus", 0.0))
	var bonus := clampf(raw_bonus, 0.0, 0.5) if is_finite(raw_bonus) else 0.0
	var base_speed: float = (Defs.WALK_SPEED * Mounts.SPEED_FACTOR
		if mounted else (Defs.SPRINT_SPEED if sprint else Defs.WALK_SPEED))
	var speed := base_speed * factor * injury_factor * (1.0 + bonus)
	if mounted:
		# Surface, uphill drag and limited downhill boost are deterministic for both peers.
		speed *= BikeTerrain.speed_factor(world, position, direction)
	speed *= StealthStance.speed_factor(crouching)
	return move(world, position, direction, speed, delta)


## Moves along `direction` (unit or shorter) at `speed` meters per second. Shared by players and zombies.
static func move(world, position: Vector3, direction: Vector2, speed: float, delta: float) -> Vector3:
	delta = clampf(delta, 0.0, MAX_DELTA)
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	var target := Vector2(position.x, position.z) + direction * speed * delta
	# Try the full move, then each axis alone, so the mover slides along walls and shores.
	var candidates: Array[Vector2] = [target, Vector2(target.x, position.z), Vector2(position.x, target.y)]
	for candidate in candidates:
		if _is_free(world, candidate):
			return Vector3(candidate.x, world.height_at(candidate.x, candidate.y), candidate.y)
	return Vector3(position.x, world.height_at(position.x, position.z), position.z)


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


static func _is_free(world, point: Vector2) -> bool:
	# Wading is allowed until the water is deeper than a meter.
	if world.height_at(point.x, point.y) < Defs.WATER_LEVEL - 1.0:
		return false
	for blocker in world.blockers_near(point.x, point.y, Defs.PLAYER_RADIUS + 1.0):
		var offset := Vector2(blocker["x"] - point.x, blocker["z"] - point.y)
		if offset.length() < Defs.PLAYER_RADIUS + float(blocker["radius"]):
			return false
	return true
