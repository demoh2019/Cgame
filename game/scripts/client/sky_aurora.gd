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


## Milky Way strength: dark clear nights on High/Ultra only (dimmed while the moon is full).
static func milky_way_strength(level: int, daylight: float, storm: float, moon_phase: float) -> float:
	if level < 2:
		return 0.0
	var moon_glare: float = 1.0 - 0.6 * clampf(1.0 - absf(moon_phase - 0.5) * 2.0, 0.0, 1.0)
	if not is_finite(daylight) or not is_finite(storm):
		return 0.0
	var night: float = 1.0 - smoothstep(0.04, 0.3, clampf(daylight, 0.0, 1.0))
	var clear: float = 1.0 - smoothstep(0.1, 0.6, clampf(storm, 0.0, 1.0))
	return night * clear * moon_glare
