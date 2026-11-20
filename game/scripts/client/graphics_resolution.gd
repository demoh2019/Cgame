extends RefCounted
## Pure renderer-aware upscale/antialiasing policy; mobile and GL Compatibility
## do not support Godot 4 Forward+ FSR2 or independent 3D resolution buffers.


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
			"screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED}
	# On GL Compatibility and Mobile, native resolution is the honest fallback.
	return {"mode": Viewport.SCALING_3D_MODE_BILINEAR, "scale": 1.0,
		"msaa": msaa,
		"screen_space_aa": Viewport.SCREEN_SPACE_AA_FXAA if msaa == Viewport.MSAA_DISABLED else Viewport.SCREEN_SPACE_AA_DISABLED}


static func apply(viewport: Viewport, settings: Dictionary) -> void:
	if viewport == null:
		return
	viewport.msaa_3d = settings["msaa"]
	viewport.use_taa = false
	viewport.screen_space_aa = settings["screen_space_aa"]
	viewport.scaling_3d_mode = settings["mode"]
	viewport.scaling_3d_scale = float(settings["scale"])
