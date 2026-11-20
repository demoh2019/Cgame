extends RefCounted
## One renderer-native filmic curve, shared by online and offline worlds.
## AgX is native in this Cgame engine fork; ACES remains the low-cost fallback.
## There is no LUT, extra postprocessing pass, or additional render target.

static func settings(level: int, rendering_method: String) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	var use_agx: bool = tier >= 2 and rendering_method == "forward_plus"
	return {
		"mode": Environment.TONE_MAPPER_AGX if use_agx else Environment.TONE_MAPPER_ACES,
		"agx_white": 12.5 if tier == 2 else 16.29,
		"agx_contrast": 1.20 if tier == 2 else 1.26,
		"aces_white": 6.0,
	}


static func apply(env: Environment, level: int, rendering_method: String) -> void:
	if env == null:
		return
	var profile: Dictionary = settings(level, rendering_method)
	var target: int = int(profile["mode"])
	if env.tonemap_mode != target:
		env.tonemap_mode = target
	if target == Environment.TONE_MAPPER_AGX:
		# Update native fork properties only when their preset actually changes.
		var white: float = float(profile["agx_white"])
		var contrast: float = float(profile["agx_contrast"])
		if not is_equal_approx(env.tonemap_agx_white, white):
			env.tonemap_agx_white = white
		if not is_equal_approx(env.tonemap_agx_contrast, contrast):
			env.tonemap_agx_contrast = contrast
	elif not is_equal_approx(env.tonemap_white, float(profile["aces_white"])):
		env.tonemap_white = float(profile["aces_white"])
