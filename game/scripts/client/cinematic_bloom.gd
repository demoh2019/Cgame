extends RefCounted
## HDR camera-lens bloom tuned for sky, weather and golden-hour lighting.
## High/Ultra reuse the existing Godot native glow chain; no extra pass,
## blur material, extra emissive objects or separate screen texture.
const CinematicColorGrade = preload("res://scripts/client/cinematic_color_grade.gd")


## Pure scene-referred optics policy. Quantizing to hundredths both bounds
## the look and avoids repeated C++ environment updates as weather eases.
static func look(level: int, method: String, daylight: float,
		sun_height: float, storm: float) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	var grade: Dictionary = CinematicColorGrade.look(daylight, sun_height, storm)
	var premium: bool = method == "forward_plus" and tier >= 2
	var day: float = clampf(daylight, 0.0, 1.0)
	var clouds: float = clampf(storm, 0.0, 1.0)
	var sunset: float = (1.0 - smoothstep(0.10, 0.48, absf(sun_height))) * smoothstep(0.08, 0.35, day)
	var night: float = 1.0 - day
	var weight: float = (0.72 if tier == 2 else 1.0) if premium else 0.0
	# Keep direct solar surfaces crisp at midday; favor bright lamps,
	# torch flames and golden-hour scattering only when justified.
	var intensity: float = float(grade["glow_intensity"]) + weight * (0.040 * night + 0.035 * sunset)
	var threshold: float = lerpf(1.10,
		clampf(1.22 - 0.20 * sunset - 0.17 * night + 0.08 * clouds, 0.94, 1.32), weight)
	var bloom: float = lerpf(0.06,
		clampf(0.045 + 0.018 * sunset + 0.012 * night, 0.04, 0.08), weight)
	return {
		"intensity": roundf(clampf(intensity, 0.30, 0.72) * 100.0) / 100.0,
		"threshold": roundf(clampf(threshold, 0.94, 1.32) * 100.0) / 100.0,
		"bloom": roundf(clampf(bloom, 0.04, 0.08) * 100.0) / 100.0,
		"premium": premium,
	}


static func apply(environment: Environment, level: int, method: String,
		daylight: float, sun_height: float, storm: float) -> void:
	if environment == null:
		return
	var p: Dictionary = look(level, method, daylight, sun_height, storm)
	var intensity: float = float(p["intensity"])
	var threshold: float = float(p["threshold"])
	var bloom: float = float(p["bloom"])
	# The engine setter independently skips identical state, but checking
	# here also saves GDScript property traffic to native C++.
	if absf(environment.glow_intensity - intensity) >= 0.005:
		environment.glow_intensity = intensity
	if absf(environment.glow_hdr_threshold - threshold) >= 0.005:
		environment.glow_hdr_threshold = threshold
	if absf(environment.glow_bloom - bloom) >= 0.005:
		environment.glow_bloom = bloom
