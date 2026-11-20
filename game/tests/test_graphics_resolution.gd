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
	t.check(bool(Quality.profile(2)["ssao"]) and not bool(Quality.profile(2)["ssil"]),
		"High has contact shadows without Ultra indirect light")
	t.current = "desktop modern, legacy devices supported"
	t.eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"forward_plus", "modern desktop default")
	t.eq(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile"),
		"gl_compatibility", "mobile compatibility")
	t.eq(ProjectSettings.get_setting("rendering/renderer/rendering_method.web"),
		"gl_compatibility", "web compatibility")
