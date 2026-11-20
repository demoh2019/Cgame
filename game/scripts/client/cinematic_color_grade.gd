extends RefCounted
## Scene-referred cinematic grade, inspired by filmic Unreal/HDRP color pipelines.
## Reuse the engine-native ACES/AgX tonemapper: changing Environment uniforms
## adds no fullscreen pass, LUT upload or material/mesh rebuild.
##
## Deliberately subtle: normal midday albedo remains recognisable, evening has
## warm atmospheric contrast, moonlight stays readable without crushing blacks,
## and overcast storms reduce contrast and saturation like real diffuse light.


static func look(daylight: float, sun_height: float, storm: float) -> Dictionary:
	var day: float = clampf(daylight, 0.0, 1.0)
	var overcast: float = clampf(storm, 0.0, 1.0)
	# Warm, low-angle sun is most pronounced near sunrise/sunset, not midnight.
	var horizon_sun: float = 1.0 - smoothstep(0.08, 0.42, absf(sun_height))
	var dusk: float = horizon_sun * smoothstep(0.08, 0.35, day)
	var exposure: float = lerpf(0.96, 0.85, day) + 0.025 * dusk - 0.055 * overcast
	var contrast: float = lerpf(1.035, 1.09, day) - 0.06 * overcast
	var saturation: float = lerpf(0.82, 1.035, day) + 0.02 * dusk - 0.17 * overcast
	# Bloom is handled by the existing per-preset glow-enabled budget.
	var glow: float = lerpf(0.48, 0.55, day) + 0.065 * dusk - 0.055 * overcast
	return {
		"exposure": clampf(exposure, 0.75, 1.05),
		"contrast": clampf(contrast, 0.94, 1.12),
		"saturation": clampf(saturation, 0.64, 1.09),
		"glow_intensity": clampf(glow, 0.34, 0.68),
	}


static func apply(environment: Environment, daylight: float, sun_height: float, storm: float) -> void:
	if environment == null:
		return
	var p: Dictionary = look(daylight, sun_height, storm)
	environment.tonemap_exposure = float(p["exposure"])
	environment.adjustment_contrast = float(p["contrast"])
	environment.adjustment_saturation = float(p["saturation"])
	environment.glow_intensity = float(p["glow_intensity"])
