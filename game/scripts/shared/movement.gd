extends RefCounted
## One step of player movement. The server runs it to decide where a player is, and the client runs
## the very same function to predict its own player, so the two agree except when something the
## client could not know (another player is not an obstacle here) intervenes.

const Defs = preload("res://scripts/shared/defs.gd")

const MAX_DELTA := 0.1 # A longer step is clamped, so a lag spike cannot teleport a player.


## `input` has "x", "z" (a move direction, any length up to 1) and "sprint". Returns the new position
## (y follows the ground). Water that is too deep and solid objects stop the player, and sliding
## along them keeps the movement smooth.
static func step(world, position: Vector3, input: Dictionary, delta: float) -> Vector3:
	delta = clampf(delta, 0.0, MAX_DELTA)
	var direction := Vector2(float(input.get("x", 0.0)), float(input.get("z", 0.0)))
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	if direction == Vector2.ZERO or delta == 0.0:
		return Vector3(position.x, world.height_at(position.x, position.z), position.z)
	# The server supplies this from its authoritative inventory, never from a network value.
	# With no factor (legacy/test inputs), movement stays unchanged.
	var factor := clampf(float(input.get("cargo_factor", 1.0)), Defs.CARRY_MIN_SPEED_FACTOR, 1.0)
	var sprint := bool(input.get("sprint", false)) and factor >= 0.9999
	# Skill bonus to movement speed: the server supplies it from the character's skills, the client
	# from the snapshot, so prediction matches. Capped so a forged input cannot run away.
	var bonus := clampf(float(input.get("speed_bonus", 0.0)), 0.0, 0.5)
	var speed := (Defs.SPRINT_SPEED if sprint else Defs.WALK_SPEED) * factor * (1.0 + bonus)
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


static func _is_free(world, point: Vector2) -> bool:
	# Wading is allowed until the water is deeper than a meter.
	if world.height_at(point.x, point.y) < Defs.WATER_LEVEL - 1.0:
		return false
	for blocker in world.blockers_near(point.x, point.y, Defs.PLAYER_RADIUS + 1.0):
		var offset := Vector2(blocker["x"] - point.x, blocker["z"] - point.y)
		if offset.length() < Defs.PLAYER_RADIUS + float(blocker["radius"]):
			return false
	return true
