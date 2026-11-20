extends RefCounted
## Cinematic time-of-day color separation for Albion After.
## Pure deterministic math: no textures, noise, extra fullscreen passes or
## server state. The existing post material receives two vec3 uniforms at 5 Hz.

const BASE_SHADOW := Vector3(-0.012, 0.0, 0.025)
const BASE_HIGHLIGHT := Vector3(0.030, 0.015, -0.020)


static func palette(daylight: float, sun_height: float, storm: float,
		underground: bool = false) -> Dictionary:
	var day: float = clampf(daylight, 0.0, 1.0)
	var overcast: float = clampf(storm, 0.0, 1.0)
	var night: float = 1.0 - day
	# Golden hour is a narrow band around the horizon, only while the sky is lit.
	var golden_hour: float = (
		(1.0 - smoothstep(0.04, 0.40, absf(sun_height)))
		* smoothstep(0.10, 0.40, day) * (1.0 - overcast * 0.80)
	)
	var shadows: Vector3 = (
		BASE_SHADOW + Vector3(-0.012, -0.006, 0.020) * night
		+ Vector3(-0.002, -0.008, 0.014) * overcast
	)
	var highlights: Vector3 = (
		BASE_HIGHLIGHT + Vector3(0.026, 0.012, -0.024) * golden_hour
		+ Vector3(-0.014, -0.004, 0.017) * night
		+ Vector3(-0.018, -0.013, 0.018) * overcast
	)
	if underground:
		# Leave lit torches warm, keep the unlit stone slightly cool.
		shadows = Vector3(-0.009, -0.008, 0.023)
		highlights = Vector3(0.043, 0.019, -0.034)
	return {"shadow_tone": shadows, "highlight_tone": highlights}


static func apply(material: ShaderMaterial, daylight: float, sun_height: float,
		storm: float, underground: bool = false) -> void:
	if material == null:
		return
	var tones: Dictionary = palette(daylight, sun_height, storm, underground)
	material.set_shader_parameter("shadow_tone", tones["shadow_tone"])
	material.set_shader_parameter("highlight_tone", tones["highlight_tone"])
