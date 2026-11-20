extends RefCounted
## First-sighting cover for infected. Reuses authoritative bullet geometry,
## including procedural solids and player-built barricades. Not a client RPC.
const RangedCover = preload("res://scripts/shared/ranged_cover.gd")

const CLOSE_CONTACT := 0.2
const END_TOLERANCE := 0.08


static func clear_path(world, origin: Vector3, target: Vector3) -> bool:
	if world == null or not origin.is_finite() or not target.is_finite():
		return false
	var start := Vector2(origin.x, origin.z)
	var offset := Vector2(target.x - origin.x, target.z - origin.z)
	var distance_squared: float = offset.length_squared()
	if not is_finite(distance_squared):
		return false
	# Two entities at the same point cannot be separated by a wall.
	if distance_squared <= CLOSE_CONTACT * CLOSE_CONTACT:
		return true
	var distance: float = sqrt(distance_squared)
	return RangedCover.first_blocker_distance(world, start, offset, distance) >= distance - END_TOLERANCE
