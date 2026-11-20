extends RefCounted
## Sun-filtered shallow-water caustic strength shared by all game terrain.
## Profile selection is GPU global; weather updates only one scalar at 5 Hz.
## No CPU texture generation, scene nodes or per-chunk material duplication.

const UPDATES_PER_SECOND := 5.0


static func light_factor(daylight: float, sun_height: float, storm: float) -> float:
	if not is_finite(daylight) or not is_finite(sun_height) or not is_finite(storm):
		return 0.0
	var day: float = smoothstep(0.12, 0.72, clampf(daylight, 0.0, 1.0))
	var sun: float = smoothstep(0.04, 0.38, clampf(sun_height, -1.0, 1.0))
	var overcast: float = 1.0 - clampf(storm, 0.0, 1.0) * 0.92
	return clampf(day * sun * overcast, 0.0, 1.0)


## Only Forward+ High/Ultra spends GPU cycles on fine water patterns.
## A disabled shader global lets low-end renderers avoid the near-field math.
static func quality_strength(level: int, rendering_method: String) -> float:
	if rendering_method != "forward_plus":
		return 0.0
	match clampi(level, 0, 3):
		2:
			return 0.55
		3:
			return 1.0
	return 0.0
