extends RefCounted
## Cinematic green/violet night curtains; driven by existing world weather.
## The entire shader branch is skipped outside mountain nights or on
## unsupported renderers, with stable fractional strength at transitions.

static func strength(level: int, daylight: float, storm: float,
		biome: String = "mountain", method: String = "forward_plus") -> float:
	if level < 2 or method != "forward_plus" or biome != "mountain":
		return 0.0
	if not is_finite(daylight) or not is_finite(storm):
		return 0.0
	if daylight >= 0.24 or storm >= 0.80:
		return 0.0
	# High is subtle; Ultra allows stronger colorful folded ribbons.
	var maximum: float = 0.30 if level == 2 else 0.65
	var night: float = 1.0 - smoothstep(0.04, 0.24, clampf(daylight, 0.0, 1.0))
	var clear: float = 1.0 - smoothstep(0.15, 0.80, clampf(storm, 0.0, 1.0))
	return maximum * night * clear
