extends RefCounted
## Server-owned coordinated infected focus for classless survivor parties.
## All spatial checks use live entity positions; clients send no enemy ID.

const RANGE := 24.0
const HEIGHT_LIMIT := 4.0
const DURATION := 18.0
const COOLDOWN := 28.0
const DAMAGE_BONUS := 0.08


static func in_range(source: Vector3, target: Vector3) -> bool:
	if not source.is_finite() or not target.is_finite():
		return false
	if absf(source.y - target.y) > HEIGHT_LIMIT:
		return false
	var planar := Vector2(source.x - target.x, source.z - target.z)
	return planar.length_squared() <= RANGE * RANGE


## Called only for already-authorized server-side infected attacks.
static func damage(base: float, qualified: bool) -> float:
	if not is_finite(base) or base <= 0.0 or not qualified:
		return base
	return base * (1.0 + DAMAGE_BONUS)
