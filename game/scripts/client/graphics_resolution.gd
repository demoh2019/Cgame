extends RefCounted
## Pure renderer-aware upscale/antialiasing policy; mobile and GL Compatibility
## do not support Godot 4 Forward+ FSR2 or independent 3D resolution buffers.


## FSR2 already owns its RCAS sharpening stage. At lower internal resolutions
## restore a little more microdetail without adding a second fullscreen pass.
## Godot uses 0 = sharpest and 2 = softest; avoid ringing at low scales.
static func fsr_sharpness_for_scale(render_scale: float) -> float:
	var scale: float = clampf(render_scale if is_finite(render_scale) else 1.0, 0.5, 1.0)
	return clampf(0.25 - (1.0 - scale) * 0.35, 0.12, 0.25)


static func plan(method: String, profile: Dictionary,
		requested_scale: float = -1.0, adaptive: bool = false) -> Dictionary:
	var scale: float = float(profile.get("scale", 1.0))
	if is_finite(requested_scale) and requested_scale >= 0.0:
		scale = requested_scale
	scale = clampf(scale, 0.5, 1.0)
	var msaa: int = int(profile.get("msaa", Viewport.MSAA_DISABLED))
	# FSR2 is temporal AA itself, including at full-resolution (adaptive).
	if method == "forward_plus" and (adaptive or scale < 0.995):
		return {"mode": Viewport.SCALING_3D_MODE_FSR2,
			"scale": scale, "msaa": Viewport.MSAA_DISABLED,
			"fsr_sharpness": fsr_sharpness_for_scale(scale),
			"screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED}
	# On GL Compatibility and Mobile, native resolution is the honest fallback.
	return {"mode": Viewport.SCALING_3D_MODE_BILINEAR, "scale": 1.0,
		"msaa": msaa, "fsr_sharpness": 0.2,
		"screen_space_aa": Viewport.SCREEN_SPACE_AA_FXAA if msaa == Viewport.MSAA_DISABLED else Viewport.SCREEN_SPACE_AA_DISABLED}


static func apply(viewport: Viewport, settings: Dictionary) -> void:
	if viewport == null:
		return
	# The engine owns FSR2 camera-cut resets. Reapplying the same graphics
	# profile must not needlessly perturb the viewport's temporal pipeline.
	if viewport.msaa_3d != int(settings["msaa"]):
		viewport.msaa_3d = settings["msaa"]
	if viewport.use_taa:
		viewport.use_taa = false
	if viewport.screen_space_aa != int(settings["screen_space_aa"]):
		viewport.screen_space_aa = settings["screen_space_aa"]
	if viewport.scaling_3d_mode != int(settings["mode"]):
		viewport.scaling_3d_mode = settings["mode"]
	if not is_equal_approx(viewport.scaling_3d_scale, float(settings["scale"])):
		viewport.scaling_3d_scale = float(settings["scale"])
	if not is_equal_approx(viewport.fsr_sharpness, float(settings.get("fsr_sharpness", 0.2))):
		viewport.fsr_sharpness = float(settings.get("fsr_sharpness", 0.2))
