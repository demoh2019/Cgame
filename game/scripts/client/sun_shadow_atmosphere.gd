extends RefCounted
## Atmospheric shadow filtering in native Godot DirectionalLight3D.
## Only High/Ultra use variable penumbrae; no additional light or pass.
const GraphicsLighting = preload("res://scripts/client/graphics_lighting.gd")


static func profile(level: int, daylight: float, sun_height: float,
		storm: float) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	var base_blur: float = float(GraphicsLighting.settings(tier, "forward_plus")["shadow_blur"])
	if tier < 2 or not is_finite(daylight) or not is_finite(sun_height) or not is_finite(storm):
		return {"blur": base_blur, "opacity": 1.0}
	var day: float = clampf(daylight, 0.0, 1.0)
	var overcast: float = clampf(storm, 0.0, 1.0)
	var near_horizon: float = 1.0 - smoothstep(0.10, 0.55, absf(sun_height))
	var dusk: float = near_horizon * smoothstep(0.08, 0.38, day)
	# Overcast sky scatters direct light: weaker and softer shadows.
	# The angular filter is the existing renderer implementation.
	var blur: float = base_blur * (1.0 + dusk * 0.15 + overcast * 0.27)
	var opacity: float = (0.72 + 0.28 * day) * (1.0 - 0.42 * overcast)
	return {"blur": clampf(blur, base_blur, base_blur * 1.5),
		"opacity": clampf(opacity, 0.40, 1.0)}


static func apply(sun: DirectionalLight3D, level: int, daylight: float,
		sun_height: float, storm: float) -> void:
	if sun == null:
		return
	var p: Dictionary = profile(level, daylight, sun_height, storm)
	# This controller owns ONLY penumbra width. SunShadowQuality owns
	# directional shadow opacity at 5 Hz; two clocks writing the same
	# property produced visible light/shadow flicker in changing weather.
	# Quantization and the 4 Hz caller avoid per-frame renderer traffic.
	var blur: float = roundf(float(p["blur"]) * 100.0) / 100.0
	if not is_equal_approx(sun.shadow_blur, blur):
		sun.shadow_blur = blur
