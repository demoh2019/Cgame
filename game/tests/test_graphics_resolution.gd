extends RefCounted
## No-GPU validation of rendering backends, FSR2 and full-res fallback.
const Resolution = preload("res://scripts/client/graphics_resolution.gd")
const Quality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "Forward+ temporal upscaling without duplicate AA"
	var p: Dictionary = Resolution.plan("forward_plus", Quality.profile(1))
	t.eq(p["mode"], Viewport.SCALING_3D_MODE_FSR2, "Balanced uses FSR2")
	t.near(float(p["scale"]), 0.77, 0.0001, "Balanced native-upscale fraction")
	t.eq(p["msaa"], Viewport.MSAA_DISABLED, "no redundant MSAA")
	t.check(float(p["fsr_sharpness"]) < 0.2,
		"Balanced recovers fine texture detail with native FSR2 RCAS")
	t.eq(p["screen_space_aa"], Viewport.SCREEN_SPACE_AA_DISABLED,
		"FSR2 is its own antialiasing")
	p = Resolution.plan("forward_plus", Quality.profile(3))
	t.eq(p["mode"], Viewport.SCALING_3D_MODE_BILINEAR, "manual Ultra is native")
	t.eq(p["msaa"], Viewport.MSAA_4X, "manual Ultra retains MSAA4")
	p = Resolution.plan("forward_plus", Quality.profile(3), 0.86, true)
	t.eq(p["mode"], Viewport.SCALING_3D_MODE_FSR2, "adaptive Ultra uses FSR2")
	t.near(float(p["scale"]), 0.86, 0.0001, "adaptive GPU resolution")
	t.eq(p["msaa"], Viewport.MSAA_DISABLED, "no MSAA cost in adaptive mode")
	t.check(float(p["fsr_sharpness"]) > 0.12,
		"high-resolution adaptive FSR2 reduces excessive sharpening")
	p = Resolution.plan("forward_plus", Quality.profile(3), 1.0, true)
	t.eq(p["mode"], Viewport.SCALING_3D_MODE_FSR2, "native FSR2 temporal AA")
	t.near(float(p["fsr_sharpness"]), 0.25, 0.0001,
		"native temporal AA uses gentler RCAS")
	t.current = "FSR2 quality recovers stable fine detail at lower resolutions"
	var previous: float = -1.0
	for scale in [0.5, 0.59, 0.77, 0.86, 1.0]:
		var sharpness: float = Resolution.fsr_sharpness_for_scale(scale)
		t.check(sharpness >= 0.12 and sharpness <= 0.25,
			"the integrated sharpening budget avoids extreme ringing")
		t.check(sharpness >= previous,
			"less upscaling requires less sharpening")
		previous = sharpness
	t.near(Resolution.fsr_sharpness_for_scale(NAN), 0.25, 0.0001,
		"invalid sharpness inputs fall back to native resolution")
	t.near(Resolution.fsr_sharpness_for_scale(INF), 0.25, 0.0001,
		"infinite sharpness inputs cannot reach the GPU")
	t.current = "unsupported renderer never gets invalid FSR2 calls"
	for method in ["mobile", "gl_compatibility", "unknown"]:
		p = Resolution.plan(method, Quality.profile(1), 0.5, true)
		t.eq(p["mode"], Viewport.SCALING_3D_MODE_BILINEAR,
			"only Forward+ can run FSR2")
		t.near(float(p["scale"]), 1.0, 0.0001,
			"no falsely advertised Compatibility resolution reduction")
		t.near(float(p["fsr_sharpness"]), 0.2, 0.0001,
			"unsupported renderer resets sharpening to its safe default")
	p = Resolution.plan("forward_plus", Quality.profile(1), NAN, true)
	t.near(float(p["scale"]), 0.77, 0.0001, "NaN falls back to preset")
	p = Resolution.plan("forward_plus", Quality.profile(1), 99.0, true)
	t.near(float(p["scale"]), 1.0, 0.0001, "scale bounded to native")
	t.check(bool(Quality.profile(2)["ssao"]) and bool(Quality.profile(2)["ssil"]) and not bool(Quality.profile(2)["sdfgi"]),
		"High has bounded screen-space GI without Ultra's distance-field GI")
	t.current = "native FSR2 temporal reset is safe on live quality reapplication"
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	var adaptive_plan: Dictionary = Resolution.plan("forward_plus", Quality.profile(3), 0.86, true)
	Resolution.apply(viewport, adaptive_plan)
	t.eq(viewport.scaling_3d_mode, Viewport.SCALING_3D_MODE_FSR2,
		"playable adaptive Ultra uses native FSR2 camera temporal reconstruction")
	t.near(viewport.scaling_3d_scale, 0.86, 0.0001,
		"adaptive FSR2 preserves game graphics pixel budget")
	t.check(not viewport.use_taa,
		"FSR2 is not mixed with a second temporal anti-aliasing history")
	Resolution.apply(viewport, adaptive_plan)
	t.eq(viewport.scaling_3d_mode, Viewport.SCALING_3D_MODE_FSR2,
		"repeat quality apply preserves the active native temporal mode")
	t.near(viewport.fsr_sharpness, float(adaptive_plan["fsr_sharpness"]), 0.0001,
		"repeat quality apply keeps the existing RCAS sharpening budget")
	Resolution.apply(viewport, Resolution.plan("gl_compatibility", Quality.profile(1)))
	t.eq(viewport.scaling_3d_mode, Viewport.SCALING_3D_MODE_BILINEAR,
		"Compatibility fallback never attempts unsupported FSR2 history")
	viewport.free()
	var native_source := (Resolution as Script).source_code
	t.check(native_source.contains("if viewport.scaling_3d_mode != int(settings"),
		"live game does not reassign unchanged native scaling settings")
	t.check(native_source.contains("if not is_equal_approx(viewport.scaling_3d_scale"),
		"dynamic render scale only updates when the pixel budget changes")
	t.current = "actual game upscaler diagnostics without GPU timer overhead"
	t.eq(Resolution.diagnostic_label(Viewport.SCALING_3D_MODE_METALFX_TEMPORAL, 0.70),
		"MetalFX Temporal 70%", "optional FPS overlay identifies native Apple temporal scaler")
	t.eq(Resolution.diagnostic_label(Viewport.SCALING_3D_MODE_FSR2, 0.77),
		"FSR2 77%", "FPS overlay identifies portable AMD FSR2 reconstruction")
	t.eq(Resolution.diagnostic_label(Viewport.SCALING_3D_MODE_BILINEAR, 1.0),
		"Native 100%", "manual Ultra shows real full-resolution path")
	t.eq(Resolution.diagnostic_label(Viewport.SCALING_3D_MODE_BILINEAR, 0.6),
		"Bilinear 60%", "upscaling is not mislabelled native when scaled")
	t.eq(Resolution.diagnostic_label(Viewport.SCALING_3D_MODE_FSR2, NAN),
		"FSR2 100%", "invalid render scale cannot create misleading FPS metrics")
	var access_source: String = FileAccess.get_file_as_string(
		"res://scripts/client/ui_accessibility_layer.gd")
	t.check(access_source.contains("GraphicsResolution.diagnostic_label("),
		"actual optional game FPS overlay reports current viewport's upscaler")
	t.check(access_source.contains("if fps_label.visible:"),
		"renderer diagnostics remain disabled when overlay is hidden")
	t.current = "desktop modern, legacy devices supported"
	t.eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"forward_plus", "modern desktop default")
	t.eq(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile"),
		"gl_compatibility", "mobile compatibility")
	t.eq(ProjectSettings.get_setting("rendering/renderer/rendering_method.web"),
		"gl_compatibility", "web compatibility")


	t.current = "cheap Apple MetalFX spatial on the low presets"
	for low_level in [0, 1]:
		var cheap: Dictionary = Resolution.plan("forward_plus", Quality.profile(low_level), -1.0, false, "metal", 0.5)
		t.eq(cheap["mode"], Viewport.SCALING_3D_MODE_METALFX_SPATIAL,
			"%s skips the temporal scaler and its motion-vector pass" % Quality.NAMES[low_level])
		t.eq(cheap["screen_space_aa"], Viewport.SCREEN_SPACE_AA_FXAA, "spatial scaling keeps FXAA edges")
	t.eq(Resolution.diagnostic_label(Viewport.SCALING_3D_MODE_METALFX_SPATIAL, 0.77), "MetalFX Spatial 77%",
		"overlay names the spatial scaler")

	t.current = "native Apple MetalFX temporal and portable FSR2 fallback"
	var native: Dictionary = Resolution.plan("forward_plus", Quality.profile(2),
		0.65, true, "metal", 0.70)
	t.eq(native["mode"], Viewport.SCALING_3D_MODE_METALFX_TEMPORAL,
		"native Metal backend selects Apple's temporal upscale path")
	t.near(float(native["scale"]), 0.70, 0.00001,
		"native scaler never goes below this GPU's minimum input fraction")
	t.eq(native["msaa"], Viewport.MSAA_DISABLED,
		"MetalFX temporal handles AA without duplicate MSAA")
	t.eq(native["screen_space_aa"], Viewport.SCREEN_SPACE_AA_DISABLED,
		"MetalFX temporal owns antialiasing, not FXAA")
	var native_ultra: Dictionary = Resolution.plan("forward_plus", Quality.profile(3),
		1.0, true, "metal", 0.65)
	t.eq(native_ultra["mode"], Viewport.SCALING_3D_MODE_METALFX_TEMPORAL,
		"native MetalFX can temporally antialias at full resolution")
	for backend in ["vulkan", "d3d12", "opengl3", ""]:
		var portable: Dictionary = Resolution.plan("forward_plus", Quality.profile(1),
			0.65, true, backend, 0.65)
		t.eq(portable["mode"], Viewport.SCALING_3D_MODE_FSR2,
			"non-Metal renderer retains its fully supported FSR2 path")
	for invalid in [NAN, INF, -1.0, 0.0, 1.5]:
		var safe: Dictionary = Resolution.plan("forward_plus", Quality.profile(1),
			0.65, true, "metal", invalid)
		t.eq(safe["mode"], Viewport.SCALING_3D_MODE_FSR2,
			"invalid/unavailable hardware limits cannot select MetalFX")
	var native_manual: Dictionary = Resolution.plan("forward_plus", Quality.profile(3),
		1.0, false, "metal", 0.65)
	t.eq(native_manual["mode"], Viewport.SCALING_3D_MODE_BILINEAR,
		"manual native Ultra keeps its existing four-sample MSAA path")
	t.eq(native_manual["msaa"], Viewport.MSAA_4X,
		"manual Ultra is unchanged on Metal when not upscaling")
	var graphics_controller: String = (Quality as Script).source_code
	t.check(graphics_controller.contains("GraphicsResolution.runtime_metalfx_min_scale()")
		and graphics_controller.contains("adaptive, driver, minimum"),
		"real quality controller queries backend and native hardware before choosing")
	var multiplayer: String = FileAccess.get_file_as_string(
		"res://scripts/client/online_main.gd")
	t.check(multiplayer.contains("GraphicsQuality.metalfx_resolution_floor()"),
		"online adaptive quality cannot repeatedly ask for unsupported MetalFX scales")


	t.current = "MetalFX refuses a GPU minimum exceeding the preset pixel budget"
	var cost_sensitive: Dictionary = Resolution.plan("forward_plus", Quality.profile(0),
		0.59, true, "metal", 0.70)
	t.eq(cost_sensitive["mode"], Viewport.SCALING_3D_MODE_FSR2,
		"Performance uses FSR2 instead of exceeding its 0.59 native pixel budget")
	t.near(float(cost_sensitive["scale"]), 0.59, 0.00001,
		"Performance keeps its original shading resolution")
	var barely_missed: Dictionary = Resolution.plan("forward_plus", Quality.profile(1),
		0.70, true, "metal", 0.80)
	t.eq(barely_missed["mode"], Viewport.SCALING_3D_MODE_FSR2,
		"Balanced rejects MetalFX when its minimum exceeds 0.77")
	var affordable: Dictionary = Resolution.plan("forward_plus", Quality.profile(1),
		0.68, true, "metal", 0.70)
	t.eq(affordable["mode"], Viewport.SCALING_3D_MODE_METALFX_SPATIAL,
		"Balanced accepts MetalFX when hardware minimum fits the tier ceiling")
	t.near(float(affordable["scale"]), 0.70, 0.00001,
		"selected native MetalFX honors its minimum fraction")
	t.near(Resolution.metalfx_budget_floor(0.8, 0.77), 0.0, 0.00001,
		"a minimum exceeding tier ceiling is explicitly ineligible")
	t.near(Resolution.metalfx_budget_floor(0.7, 0.77), 0.7, 0.00001,
		"a supported scaler retains its true hardware minimum")
	for invalid_limit in [NAN, INF, -0.01, 0.0, 1.4]:
		t.near(Resolution.metalfx_budget_floor(invalid_limit, 1.0),
			0.0, 0.00001, "invalid GPU limits never enable native temporal")
	var quality_source: String = (Quality as Script).source_code
	t.check(quality_source.contains(
		"GraphicsResolution.metalfx_budget_floor("),
		"adaptive floor is derived from the exact same budget eligibility test")
	var render_source: String = (Resolution as Script).source_code
	t.check(render_source.contains(
		"device.has_feature(RenderingDevice.SUPPORTS_METALFX_TEMPORAL)"),
		"engine temporal capability is tested, not inferred from Metal driver name")
	t.check(render_source.contains(
		"RenderingDevice.LIMIT_METALFX_TEMPORAL_SCALER_MAX_SCALE"),
		"device's upper input fraction is validated before selecting MetalFX")
