extends RefCounted
## A special infected arcing attack. Server chooses the landing point and
## impact moment; the client merely renders the warning ground circle.

const MIN_ZONE := 2 # Red and black PvP/resource tiers only.
const RANGE := 12.0
const MIN_RANGE := 3.0
const RADIUS := 2.4
const WINDUP_SECONDS := 1.4
const COOLDOWN := 6.0
const INFECTION_PER_HIT := 10.0


static func spawn_chance(zone: int) -> float:
	if zone < MIN_ZONE:
		return 0.0
	return 0.08 + 0.04 * float(mini(zone, 3) - MIN_ZONE)


static func can_launch(distance: float) -> bool:
	return is_finite(distance) and distance >= MIN_RANGE and distance <= RANGE


static func hits(center: Vector2, target: Vector3) -> bool:
	if not center.is_finite() or not target.is_finite():
		return false
	var delta := Vector2(target.x, target.z) - center
	return delta.length_squared() <= RADIUS * RADIUS
