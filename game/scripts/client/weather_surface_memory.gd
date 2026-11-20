extends RefCounted
## Render-only ground moisture reservoir. Like HDRP rain/puddle material graphs,
## rain arrives quickly but surfaces dry slowly according to sun, wind and biome.
## No textures, per-chunk state, timers or game-server mechanics are allocated.
const ABSORPTION_PER_SECOND := 0.62
const DRYING_PER_SECOND := 0.008
const MAX_STEP := 0.25
const UPDATES_PER_SECOND := 5.0


static func next_wetness(previous: float, rain: float, daylight: float,
		sun_height: float, wind: Vector2, biome: String, delta: float) -> float:
	if not is_finite(previous):
		previous = 0.0
	var moisture: float = clampf(previous, 0.0, 1.0)
	if not is_finite(delta) or delta <= 0.0:
		return moisture
	var step: float = minf(delta, MAX_STEP)
	var shower: float = clampf(rain, 0.0, 1.0) if is_finite(rain) else 0.0
	var day: float = clampf(daylight, 0.0, 1.0) if is_finite(daylight) else 0.0
	var sun: float = clampf(sun_height, -1.0, 1.0) if is_finite(sun_height) else 0.0
	var wind_speed: float = wind.length() if is_finite(wind.x) and is_finite(wind.y) else 0.0
	# Quickly saturate wettable materials; avoid the discontinuity of a bool
	# storm flag changing in the middle of a GPU frame.
	moisture += (1.0 - moisture) * (1.0 - exp(-ABSORPTION_PER_SECOND * shower * step))
	# A damp forest floor retains water, while an exposed mountain dries faster.
	var biome_factor: float = 1.0
	match biome:
		"swamp":
			biome_factor = 0.42
		"forest":
			biome_factor = 0.67
		"beach":
			biome_factor = 0.85
		"mountain":
			biome_factor = 1.35
	var sun_factor: float = 0.42 + day * 0.8 + maxf(0.0, sun) * day * 0.58
	var wind_factor: float = 1.0 + minf(30.0, wind_speed) * 0.018
	# Drying stays much slower during rainfall; no unnatural alternating dry/wet flashes.
	var drying: float = DRYING_PER_SECOND * sun_factor * wind_factor * \
		biome_factor * (1.0 - 0.90 * shower)
	moisture *= exp(-drying * step)
	return clampf(moisture, 0.0, 1.0)


## GPU global updates are quantized to 5 Hz by Atmosphere, not per-pixel.
static func active_rain(storm: float) -> float:
	return clampf(storm, 0.0, 1.0) if is_finite(storm) else 0.0
