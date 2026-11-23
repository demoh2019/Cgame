extends RefCounted
## Shared server/client rules: seeded dirt roads change travel grip.
const FOOT_BONUS := 0.08
const ROAD_BIKE_GRIP := 1.04

static func coverage(world, pos: Vector3) -> float:
	if not pos.is_finite() or not world.has_method("road_coverage_at"):
		return 0.0
	var raw: float = float(world.road_coverage_at(pos.x, pos.z))
	return clampf(raw, 0.0, 1.0) if is_finite(raw) else 0.0

static func foot_factor(world, pos: Vector3, crouched: bool) -> float:
	return 1.0 if crouched else 1.0 + FOOT_BONUS * coverage(world, pos)

static func bike_surface(base: float, road: float) -> float:
	if not is_finite(base):
		return 1.0
	var actual: float = clampf(base, 0.0, 1.0)
	# A missing/corrupt road sample must never grant free asphalt-level grip.
	if not is_finite(road):
		return actual
	return lerpf(actual, maxf(actual, ROAD_BIKE_GRIP), clampf(road, 0.0, 1.0))

static func on_road(world, pos: Vector3) -> bool:
	return coverage(world, pos) >= 0.5
