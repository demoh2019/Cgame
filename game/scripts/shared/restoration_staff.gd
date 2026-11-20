extends RefCounted
## Server-side bounds for an equipment-granted, group-only healing pulse.
## No client-provided target, effect strength or range is ever accepted.

const RANGE := 8.0
const MAX_HEIGHT := 2.5
const MAX_TARGETS := 2
const BASE_HEAL := 8.0
const PER_TIER_HEAL := 4.0


static func heal_for_tier(tier: int) -> float:
	return BASE_HEAL + PER_TIER_HEAL * float(clampi(tier, 1, 4))


static func can_reach(source: Vector3, target: Vector3) -> bool:
	if not source.is_finite() or not target.is_finite():
		return false
	if absf(source.y - target.y) > MAX_HEIGHT:
		return false
	var offset := Vector2(source.x - target.x, source.z - target.z)
	return offset.length_squared() <= RANGE * RANGE


## Health deficit determines target priority; invalid and healthy actors are ignored.
static func urgency(health: float, maximum: float) -> float:
	if not is_finite(health) or not is_finite(maximum):
		return 0.0
	if maximum <= 0.0 or health <= 0.0 or health > maximum:
		return 0.0
	return maxf(0.0, maximum - health)
