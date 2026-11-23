extends RefCounted
## Deterministic directional hearing: only real, server-created sound travels
## farther downwind and less far upwind. Sight, scent and earned aggro stay intact.
const MIN_WIND_SPEED := 0.4
const FULL_WIND_SPEED := 1.6
const MAX_DIRECTIONAL_CHANGE := 0.25


## Source and listener are authoritative horizontal world positions.
## No noise can be created from silence and no detection escapes the leash.
static func radius(noise: float, wind: Vector2, source: Vector2,
		listener: Vector2, leash: float) -> float:
	if not is_finite(noise) or not is_finite(leash) or leash <= 0.0:
		return 0.0
	var original: float = clampf(noise, 0.0, leash)
	if original <= 0.0:
		return 0.0
	if not wind.is_finite() or not source.is_finite() or not listener.is_finite():
		return original
	var wind_squared: float = wind.length_squared()
	var offset: Vector2 = listener - source
	var offset_squared: float = offset.length_squared()
	# Finite vector components can still overflow squared distances.
	# Invalid propagation geometry must never boost or suppress hearing.
	if not offset.is_finite() or not is_finite(wind_squared) or \
			not is_finite(offset_squared):
		return original
	if wind_squared <= MIN_WIND_SPEED * MIN_WIND_SPEED or offset_squared < 0.0001:
		return original
	var speed: float = sqrt(wind_squared)
	var wind_factor: float = clampf((speed - MIN_WIND_SPEED) /
		(FULL_WIND_SPEED - MIN_WIND_SPEED), 0.0, 1.0)
	var direction: float = clampf(wind.normalized().dot(offset.normalized()), -1.0, 1.0)
	return clampf(original * (1.0 + MAX_DIRECTIONAL_CHANGE * wind_factor * direction),
		0.0, leash)
