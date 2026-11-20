extends RefCounted
## Premium renderer-only adaptive luminance. Artist day/night grade is retained.
const EyeAdaptation = preload("res://scripts/client/graphics_eye_adaptation.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")
const Quality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "per-renderer scene luminance cost and stability"
	for method in ["gl_compatibility", "mobile", "unknown", ""]:
		for tier in 4:
			t.check(not bool(EyeAdaptation.settings(tier, method)["enabled"]),
				"non-Forward+ renderer must never allocate auto exposure")
	for tier in [0, 1]:
		t.check(not bool(EyeAdaptation.settings(tier, "forward_plus")["enabled"]),
			"Performance and Balanced use the native fixed filmic exposure")
	for tier in [2, 3]:
		t.check(bool(EyeAdaptation.settings(tier, "forward_plus")["enabled"]),
			"High and Ultra adapt to scene brightness")
	t.eq(EyeAdaptation.settings(-99, "forward_plus"),
		EyeAdaptation.settings(0, "forward_plus"),
		"out-of-range low quality clamps")
	t.eq(EyeAdaptation.settings(99, "forward_plus"),
		EyeAdaptation.settings(3, "forward_plus"),
		"out-of-range high quality clamps")
	var high: Dictionary = EyeAdaptation.settings(2, "forward_plus")
	var ultra: Dictionary = EyeAdaptation.settings(3, "forward_plus")
	t.check(float(high["min_sensitivity"]) < float(high["max_sensitivity"]),
		"premium adaptation always has a valid bounded luminance interval")
	t.check(float(ultra["min_sensitivity"]) <= float(high["min_sensitivity"]) and
		float(ultra["max_sensitivity"]) >= float(high["max_sensitivity"]),
		"Ultra permits a wider HDR transition without losing artistic control")
	t.check(float(ultra["max_sensitivity"]) <= 200.0,
		"dark moonlit zones cannot become artificially bright as day")
	t.check(float(high["speed"]) > 0.0 and float(high["speed"]) <= 1.0,
		"gradual changes avoid exposure pumping")
	t.check(float(ultra["speed"]) >= float(high["speed"]),
		"Ultra can adapt slightly faster when moving in and out of bunkers")

	t.current = "shared WorldEnvironment uses real persistent Godot camera attributes"
	var world := WorldEnvironment.new()
	EyeAdaptation.apply(world, 1, "forward_plus")
	var camera_settings := world.camera_attributes as CameraAttributesPractical
	t.check(camera_settings != null, "persistent Godot CameraAttributesPractical is allocated")
	if camera_settings == null:
		world.free()
		return
	t.check(not camera_settings.auto_exposure_enabled,
		"low preset starts with auto exposure switched off")
	t.check(not camera_settings.dof_blur_near_enabled and
		not camera_settings.dof_blur_far_enabled,
		"upscaling budget never unexpectedly adds depth-of-field blur")
	EyeAdaptation.apply(world, 2, "forward_plus")
	t.check(camera_settings.auto_exposure_enabled,
		"High enables the actual native Forward+ luminance adjustment")
	t.near(camera_settings.auto_exposure_min_sensitivity,
		float(high["min_sensitivity"]), 0.0001,
		"camera minimum ISO is really set")
	t.near(camera_settings.auto_exposure_max_sensitivity,
		float(high["max_sensitivity"]), 0.0001,
		"camera maximum ISO is really set")
	t.near(camera_settings.auto_exposure_speed, float(high["speed"]), 0.0001,
		"camera response is smooth, not instant")
	EyeAdaptation.apply(world, 3, "forward_plus")
	t.check(world.camera_attributes == camera_settings,
		"quality switching reuses camera resource rather than rebuilding it")
	t.near(camera_settings.auto_exposure_max_sensitivity,
		float(ultra["max_sensitivity"]), 0.0001,
		"Ultra increases actual native adaptation range")
	EyeAdaptation.apply(world, 3, "gl_compatibility")
	t.check(not camera_settings.auto_exposure_enabled,
		"renderer fallback immediately frees costly auto exposure work")
	EyeAdaptation.apply(world, 3, "forward_plus")
	t.check(camera_settings.auto_exposure_enabled,
		"premium Forward+ renderer can reenable exposure after fallback")
	EyeAdaptation.apply(world, 0, "forward_plus")
	t.check(not camera_settings.auto_exposure_enabled,
		"downgrading to Performance explicitly disables auto exposure")
	EyeAdaptation.apply(null, 3, "forward_plus")
	t.check(true, "missing world environment safely skips configuration")
	world.free()

	t.current = "game atmosphere is shared online/solo and color grading remains"
	var source: String = (Atmosphere as Script).source_code
	t.check(source.contains("GraphicsEyeAdaptation.apply(world_environment"),
		"live atmospheric graphics applies premium exposure policy")
	t.check(source.contains("world_environment.environment = environment"),
		"camera exposure is applied to the same lighting rig")
	t.check(source.contains("CinematicColorGrade.apply(environment"),
		"existing weather-aware ACES color grade remains")
	t.check((Quality as Script).source_code.contains(
		'atmosphere.call("apply_graphics_profile", atmosphere_profile)'),
		"live runtime quality controls feed the shared eye adaptation")
