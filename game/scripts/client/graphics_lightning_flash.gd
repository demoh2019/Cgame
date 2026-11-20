extends RefCounted
## Event-driven storm lightning illumination. No new lights, shadow maps,
## particles, sky radiance builds, draw calls, or authoritative game changes.
## The existing sun/ambient/fog are briefly lifted after a real strike.

const DURATION := 0.46
const MAX_DISTANCE := 180.0
const BASE_STRENGTH := [0.26, 0.43, 0.66, 0.88]


## Quality controls the scene-light budget, not the hazard or network event.
static func strength(level: int) -> float:
	return BASE_STRENGTH[clampi(level, 0, BASE_STRENGTH.size() - 1)]


## Square-root falloff makes nearby strikes dramatic and distant events subtle.
static func attenuation(distance_m: float) -> float:
	if not is_finite(distance_m) or distance_m < 0.0:
		return 0.0
	var near: float = clampf(1.0 - distance_m / MAX_DISTANCE, 0.0, 1.0)
	return near * near


## Two short white/blue optical pulses (primary and softer return stroke).
## This is analytic and independent of frame rate. Zero outside DURATION.
static func sample(seconds_since_strike: float, weight: float) -> float:
	if not is_finite(seconds_since_strike) or not is_finite(weight):
		return 0.0
	if seconds_since_strike < 0.0 or seconds_since_strike >= DURATION:
		return 0.0
	var primary: float = exp(-seconds_since_strike * 23.0)
	var secondary: float = 0.28 * exp(-absf(seconds_since_strike - 0.12) * 45.0)
	var fade: float = 1.0 - smoothstep(0.28, DURATION, seconds_since_strike)
	return clampf((primary + secondary) * fade * maxf(weight, 0.0), 0.0, 1.0)


## Apply after the normal day/night, fog and quality update. Never persist
## augmented values: the atmosphere establishes the base again next frame.
static func apply(environment: Environment, sun: DirectionalLight3D,
		flash: float) -> void:
	if environment == null or sun == null or flash <= 0.0001:
		return
	var amount: float = clampf(flash, 0.0, 1.0)
	environment.ambient_light_energy += amount * 0.72
	environment.ambient_light_color = environment.ambient_light_color.lerp(
		Color(0.70, 0.80, 1.0), amount * 0.75)
	environment.fog_light_color = environment.fog_light_color.lerp(
		Color(0.72, 0.79, 0.97), amount * 0.82)
	# The existing directional light already illuminates the scene. Do not
	# allocate a second shadow-casting light for a sub-half-second strike.
	sun.light_energy += amount * 0.62
