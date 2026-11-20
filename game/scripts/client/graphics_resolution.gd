extends RefCounted
## Pure renderer-aware upscale/antialiasing policy; mobile and GL Compatibility
## do not support Godot 4 Forward+ FSR2 or independent 3D resolution buffers.


## FSR2 already owns its RCAS sharpening stage. At lower internal resolutions
## restore a little more microdetail without adding a second fullscreen pass.
## Godot uses 0 = sharpest and 2 = softest; avoid ringing at low scales.
static func fsr_sharpness_for_scale(render_scale: float) -> float:
	var scale: float = clampf(render_scale if is_finite(render_scale) else 1.0, 0.5, 1.0)
	return clampf(0.25 - (1.0 - scale) * 0.35, 0.12, 0.25)


## Read the native MetalFX hardware limit only on Metal. A zero/invalid
## limit means this device must stay on FSR2 even if its driver is Metal.
## RenderingDevice returns the limit scaled by 1,000,000.
static func metalfx_min_scale(method: String, driver: String,
		device: RenderingDevice) -> float:
	if method != "forward_plus" or driver.to_lower() != "metal" or device == null:
		return 0.0
	var raw: int = device.limit_get(RenderingDevice.LIMIT_METALFX_TEMPORAL_SCALER_MIN_SCALE)
	var limit: float = float(raw) / 1000000.0
	return limit if is_finite(limit) and limit >= 0.3 and limit <= 1.0 else 0.0


static func runtime_metalfx_min_scale() -> float:
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		return 0.0
	var device: RenderingDevice = RenderingServer.get_rendering_device()
	return metalfx_min_scale("forward_plus",
		RenderingServer.get_current_rendering_driver_name(), device)


static func plan(method: String, profile: Dictionary,
		requested_scale: float = -1.0, adaptive: bool = false,
		driver: String = "", metal_min_scale: float = 0.0) -> Dictionary:
	var scale: float = float(profile.get("scale", 1.0))
	if is_finite(requested_scale) and requested_scale >= 0.0:
		scale = requested_scale
	scale = clampf(scale, 0.5, 1.0)
	var msaa: int = int(profile.get("msaa", Viewport.MSAA_DISABLED))
	# Both temporal upscalers perform AA themselves, including at 1x in
	# adaptive mode. Native MetalFX takes precedence only on supported Metal
	# devices, with their actual minimum input scale, else FSR2 stays active.
	if method == "forward_plus" and (adaptive or scale < 0.995):
		var native_metal: bool = driver.to_lower() == "metal" and is_finite(metal_min_scale) and (
			metal_min_scale >= 0.3 and metal_min_scale <= 1.0)
		if native_metal:
			return {"mode": Viewport.SCALING_3D_MODE_METALFX_TEMPORAL,
				"scale": maxf(scale, metal_min_scale),
				"msaa": Viewport.MSAA_DISABLED,
				"fsr_sharpness": 0.2,
				"screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED}
		return {"mode": Viewport.SCALING_3D_MODE_FSR2,
			"scale": scale, "msaa": Viewport.MSAA_DISABLED,
			"fsr_sharpness": fsr_sharpness_for_scale(scale),
			"screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED}
	# On GL Compatibility and Mobile, native resolution is the honest fallback.
	return {"mode": Viewport.SCALING_3D_MODE_BILINEAR, "scale": 1.0,
		"msaa": msaa, "fsr_sharpness": 0.2,
		"screen_space_aa": Viewport.SCREEN_SPACE_AA_FXAA if msaa == Viewport.MSAA_DISABLED else Viewport.SCREEN_SPACE_AA_DISABLED}


## Diagnostics expose the backend the viewport actually selected, rather
## than a requested preset. Called only by the optional 4Hz FPS overlay.
static func diagnostic_label(mode: int, scale: float) -> String:
	var safe_scale: float = clampf(scale if is_finite(scale) else 1.0, 0.5, 1.0)
	var name: String
	match mode:
		Viewport.SCALING_3D_MODE_METALFX_TEMPORAL:
			name = "MetalFX Temporal"
		Viewport.SCALING_3D_MODE_FSR2:
			name = "FSR2"
		Viewport.SCALING_3D_MODE_BILINEAR:
			name = "Native" if safe_scale >= 0.995 else "Bilinear"
		Viewport.SCALING_3D_MODE_FSR:
			name = "FSR1"
		_:
			name = "3D upscale"
	return "%s %d%%" % [name, roundi(safe_scale * 100.0)]


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
