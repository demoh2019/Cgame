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
	t.current = "desktop modern, legacy devices supported"
	t.eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"forward_plus", "modern desktop default")
	t.eq(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile"),
		"gl_compatibility", "mobile compatibility")
	t.eq(ProjectSettings.get_setting("rendering/renderer/rendering_method.web"),
		"gl_compatibility", "web compatibility")
