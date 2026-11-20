extends RefCounted
## Scalable local illumination for Forward+ terrain, PBR structures and vegetation.
## Unlike a duplicate post shader this reuses Godot's internal half-resolution
## SSAO (horizon-based) and SSIL buffers. Compatibility and Mobile allocate none.
##
## High: focused contact AO in cracks and under objects.
## Ultra: softer contact AO plus nearby screen-space diffuse light bouncing.
## Limit SSIL radius to avoid light leaking and long undersampled streaks.

static func settings(level: int, method: String) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	var forward: bool = method == "forward_plus"
	var ao: bool = forward and tier >= 2
	var bounce: bool = forward and tier == 3
	return {
		"ssao_enabled": ao,
		"ssao_radius": 1.10 if tier == 2 else 1.30,
		"ssao_intensity": 1.20 if tier == 2 else 1.35,
		"ssao_power": 1.40 if tier == 2 else 1.50,
		"ssao_detail": 0.42 if tier == 2 else 0.54,
		"ssao_horizon": 0.07,
		"ssao_sharpness": 0.94 if tier == 2 else 0.92,
		# Keep direct sunlight and artificial lights intact. AO acts on indirect.
		"ssao_light_affect": 0.0,
		"ssil_enabled": bounce,
		"ssil_radius": 2.6,
		"ssil_intensity": 0.72,
		"ssil_sharpness": 0.94,
		"ssil_normal_rejection": 1.0,
	}


## Apply only when graphics quality changes; never animate screen-space
## buffer settings at 60 Hz or allocate a second fullscreen pass.
static func apply(environment: Environment, level: int, method: String) -> void:
	if environment == null:
		return
	var p: Dictionary = settings(level, method)
	environment.ssao_enabled = bool(p["ssao_enabled"])
	environment.ssil_enabled = bool(p["ssil_enabled"])
	if environment.ssao_enabled:
		environment.ssao_radius = float(p["ssao_radius"])
		environment.ssao_intensity = float(p["ssao_intensity"])
		environment.ssao_power = float(p["ssao_power"])
		environment.ssao_detail = float(p["ssao_detail"])
		environment.ssao_horizon = float(p["ssao_horizon"])
		environment.ssao_sharpness = float(p["ssao_sharpness"])
		environment.ssao_light_affect = float(p["ssao_light_affect"])
	if environment.ssil_enabled:
		environment.ssil_radius = float(p["ssil_radius"])
		environment.ssil_intensity = float(p["ssil_intensity"])
		environment.ssil_sharpness = float(p["ssil_sharpness"])
		environment.ssil_normal_rejection = float(p["ssil_normal_rejection"])
