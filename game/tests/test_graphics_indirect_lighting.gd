extends RefCounted
## Renderer-aware SSAO and indirect lighting budgets with actual Godot resources.
const Indirect = preload("res://scripts/client/graphics_indirect_lighting.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "renderer-aware shadowing and distance-field GI tiers"
	t.eq(Indirect.settings(-1, "forward_plus"), Indirect.settings(0, "forward_plus"),
		"negative quality tier safely clamps")
	t.eq(Indirect.settings(100, "forward_plus"), Indirect.settings(3, "forward_plus"),
		"out-of-range quality tier safely clamps")
	for method in ["gl_compatibility", "mobile", ""]:
		for tier in 4:
			var p: Dictionary = Indirect.settings(tier, method)
			t.check(not p["ssao_enabled"] and not p["ssil_enabled"] and not p["sdfgi_enabled"],
				"unsupported renderer never enables expensive indirect lighting passes")
	for tier in [0, 1]:
		var p: Dictionary = Indirect.settings(tier, "forward_plus")
		t.check(not p["ssao_enabled"] and not p["ssil_enabled"] and not p["sdfgi_enabled"],
			"Performance and Balanced stay free of indirect lighting passes")
	var high: Dictionary = Indirect.settings(2, "forward_plus")
	var ultra: Dictionary = Indirect.settings(3, "forward_plus")
	t.check(bool(high["ssao_enabled"]) and not bool(high["ssil_enabled"]),
		"High uses only bounded contact shadows")
	t.check(bool(ultra["ssao_enabled"]) and bool(ultra["sdfgi_enabled"]) and not bool(ultra["ssil_enabled"]),
		"Ultra uses AO plus offscreen SDFGI instead of overlapping SSIL")
	t.check(float(ultra["ssao_intensity"]) <= 1.5,
		"cinematic AO does not crush ambient light under vegetation")
	t.eq(int(ultra["sdfgi_cascades"]), 2, "Ultra limits costly distance-field cascades")
	t.near(float(ultra["sdfgi_min_cell_size"]), 0.5, 0.0001,
		"coarse but stable GI voxel size covers a 128m outdoor radius")
	t.check(float(ultra["sdfgi_bounce_feedback"]) <= 0.4 and float(ultra["sdfgi_energy"]) <= 0.75,
		"bounce feedback and GI energy remain bounded to prevent overexposure")
	t.check(bool(ultra["sdfgi_read_sky_light"]),
		"outdoor indirect lighting includes actual sky contribution")
	t.eq(float(ultra["ssao_light_affect"]), 0.0,
		"AO never fakes direct sun and lantern occlusion")
	var env := Environment.new()
	Indirect.apply(env, 3, "forward_plus")
	t.check(env.ssao_enabled and env.sdfgi_enabled and not env.ssil_enabled,
		"Ultra enables native SDFGI without double-screen-space bounce")
	t.near(env.ssao_radius, float(ultra["ssao_radius"]), 0.0001,
		"fine contact AO radius is applied")
	t.eq(env.sdfgi_cascades, 2, "two bounded GPU GI cascades were applied")
	t.near(env.sdfgi_min_cell_size, 0.5, 0.0001, "native GI uses coarse cell size")
	t.near(env.sdfgi_energy, 0.72, 0.0001, "indirect lighting does not overwhelm direct light")
	t.check(env.sdfgi_read_sky_light, "sky-scattered light reaches indirect lighting")
	Indirect.apply(env, 2, "forward_plus")
	t.check(env.ssao_enabled and not env.ssil_enabled and not env.sdfgi_enabled,
		"live Ultra-to-High switches off SDFGI and retains contact AO")
	Indirect.apply(env, 3, "gl_compatibility")
	t.check(not env.ssao_enabled and not env.ssil_enabled and not env.sdfgi_enabled,
		"renderer fallback switches off unsupported GI buffers")
	Indirect.apply(env, 3, "mobile")
	t.check(not env.ssao_enabled and not env.ssil_enabled and not env.sdfgi_enabled,
		"mobile never enables Forward+ effects")
	t.check(GraphicsQuality.profile(3)["sdfgi"] and not GraphicsQuality.profile(3)["ssil"],
		"Ultra's visible preset matches the SDFGI renderer budget")
