extends RefCounted
## Regional weather becomes one GPU wind vector for all instanced vegetation.
## xy = direction, z = strength 0..1. No changes to authoritative simulation.
const MAX_SPEED := 1.5
const RESPONSE := 4.0
## Latest published wind for CPU-side effects (lanterns, smoke). Reading the shader
## global back is editor-only and returns null in exported or running games.
static var current := Vector3.ZERO

static func target(wind: Vector2) -> Vector3:
	if not wind.is_finite():
		return Vector3.ZERO
	var speed: float = wind.length()
	if not is_finite(speed) or speed < 0.0001:
		return Vector3.ZERO
	var unit: Vector2 = wind / speed
	return Vector3(unit.x, unit.y, clampf(speed / MAX_SPEED, 0.0, 1.0))

static func smooth(previous: Vector3, next: Vector3, delta: float) -> Vector3:
	if not is_finite(delta) or delta <= 0.0:
		return previous
	if not previous.is_finite() or not next.is_finite():
		return Vector3.ZERO
	return previous.lerp(next, 1.0 - exp(-RESPONSE * minf(delta, 0.25)))
