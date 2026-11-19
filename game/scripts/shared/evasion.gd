extends RefCounted
## Shared collision-aware dodge geometry. All rule enforcement is on GameServer.
## Keep the displacement in short steps so a dodge cannot jump through thin walls.

const Movement = preload("res://scripts/shared/movement.gd")
const STAMINA_COST := 24.0
const COOLDOWN := 3.0
const INVULNERABLE_TO_INFECTED := 0.30
const ATTACK_LOCK := 0.32
const SPEED := 8.0
const STEP := 0.08
const STEPS := 4
const MIN_DISPLACEMENT := 0.08


static func destination(world, origin: Vector3, input_direction: Vector2) -> Vector3:
	if not origin.is_finite() or not input_direction.is_finite():
		return origin
	if input_direction.length_squared() < 0.0001:
		return origin
	var direction := input_direction.normalized()
	var position := origin
	for i in STEPS:
		var next_position: Vector3 = Movement.move(world, position, direction, SPEED, STEP)
		if Vector2(next_position.x - position.x, next_position.z - position.z).length_squared() < 0.000001:
			break
		position = next_position
	return position


static func moved_distance(origin: Vector3, destination_position: Vector3) -> float:
	return Vector2(destination_position.x - origin.x,
		destination_position.z - origin.z).length()
