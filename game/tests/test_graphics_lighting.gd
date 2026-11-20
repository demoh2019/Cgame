extends RefCounted
## Lighting quality must remain scalable on Compatibility while offering
## cinematic cascades and volumetric depth only on supported PC GPUs.
const GraphicsLighting = preload("res://scripts/client/graphics_lighting.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")
const LocalPreview = preload("res://scripts/client/client_main.gd")


func run(t) -> void:
	t.current = "renderer-aware lighting budgets"
	t.eq(GraphicsLighting.settings(-900, "gl_compatibility"),
		GraphicsLighting.settings(0, "gl_compatibility"),
		"negative graphics tier clamps to Performance")
	t.eq(GraphicsLighting.settings(999, "forward_plus"),
		GraphicsLighting.settings(3, "forward_plus"),
		"high graphics tier clamps to Ultra")
	t.eq(int(GraphicsLighting.settings(0, "forward_plus")["shadow_cascades"]), 0,
		"Performance skips all sun cascades")
	t.eq(int(GraphicsLighting.settings(1, "forward_plus")["shadow_cascades"]), 2,
		"Balanced reserves two splits")
	t.eq(int(GraphicsLighting.settings(2, "forward_plus")["shadow_cascades"]), 2,
		"High uses two stable cascades, reducing shadow draw cost")
	t.eq(int(GraphicsLighting.settings(3, "forward_plus")["shadow_cascades"]), 4,
		"Ultra sharpens close shadows with four cascades")
	t.check(bool(GraphicsLighting.settings(2, "forward_plus")["volumetric_fog"]),
		"High uses a short, budgeted Forward+ froxel volume")
	t.check(bool(GraphicsLighting.settings(3, "forward_plus")["volumetric_fog"]),
		"Ultra uses supported Forward+ 3D fog")
	t.check(not bool(GraphicsLighting.settings(3, "gl_compatibility")["volumetric_fog"]),
		"Compatibility Ultra never enables unsupported volume passes")
	t.check(not bool(GraphicsLighting.settings(3, "mobile")["volumetric_fog"]),
		"mobile renderer avoids volumetric cost")
	t.check(not bool(GraphicsLighting.settings(0, "forward_plus")["volumetric_fog"]),
		"low-end Forward+ renders without volume allocation")

	t.current = "renderer-aware reflection ray budget"
	for tier in [0, 1]:
		t.check(not bool(GraphicsLighting.settings(tier, "forward_plus")["ssr_enabled"]),
			"Performance and Balanced never allocate the SSR pass")
	t.check(bool(GraphicsLighting.settings(2, "forward_plus")["ssr_enabled"]),
		"High reserves short half-resolution reflected rays for glossy materials")
	t.check(bool(GraphicsLighting.settings(3, "forward_plus")["ssr_enabled"]),
		"Ultra enables cinematic on-screen reflections")
	t.eq(int(GraphicsLighting.settings(2, "forward_plus")["ssr_max_steps"]), 24,
		"High limits per-pixel SSR ray travel")
	t.eq(int(GraphicsLighting.settings(3, "forward_plus")["ssr_max_steps"]), 48,
		"Ultra raises SSR quality without unbounded sampling")
	for method in ["gl_compatibility", "mobile", ""]:
		for tier in 4:
			t.check(not bool(GraphicsLighting.settings(tier, method)["ssr_enabled"]),
				"unsupported render methods never schedule screen-space reflection passes")
	t.check(float(GraphicsLighting.settings(3, "forward_plus")["ssr_depth_tolerance"]) > 0.0,
		"SSR depth tolerance remains positive to tolerate complex ruin geometry")

	t.current = "actual Godot sun and environment properties follow presets"
	var sun := DirectionalLight3D.new()
	var env := Environment.new()
	GraphicsLighting.apply(sun, env, 3, "forward_plus")
	t.eq(sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		"Ultra applies the real Godot four-cascade shadow mode")
	t.check(sun.directional_shadow_blend_splits,
		"High-quality cascades blend to reduce transition seams")
	t.check(env.volumetric_fog_enabled,
		"Ultra Forward+ activates actual environment fog")
	t.check(env.ssr_enabled, "Ultra applies the Godot environment SSR flag")
	t.eq(env.ssr_max_steps, 48, "Ultra reflection ray budget is applied to the environment")
	t.near(env.ssr_depth_tolerance, 0.20, 0.0001, "depth tolerance reduces reflection holes")
	t.near(env.volumetric_fog_length, 72.0, 0.01,
		"volumetric fog stops within bounded camera range")
	GraphicsLighting.apply(sun, env, 2, "forward_plus")
	t.check(env.volumetric_fog_enabled and env.volumetric_fog_length < 72.0,
		"High trades volume range for fog precision and bounded cost")
	t.check(env.ssr_enabled and env.ssr_max_steps == 24,
		"High reduces reflection steps after a live quality switch")
	GraphicsLighting.apply(sun, env, 1, "gl_compatibility")
	t.eq(sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		"Compatibility Balanced retains efficient two-split shadows")
	t.check(not sun.directional_shadow_blend_splits,
		"Balanced saves work from blending shadow cascades")
	t.check(not env.volumetric_fog_enabled,
		"switching renderer or preset releases the fog effect")
	t.check(not env.ssr_enabled,
		"switching to Compatibility immediately disables unsupported reflection work")
	GraphicsLighting.apply(sun, env, 0, "gl_compatibility")
	t.eq(sun.directional_shadow_mode, DirectionalLight3D.SHADOW_ORTHOGONAL,
		"Performance uses a cheap shadow mode if sun shadows are later enabled")
	GraphicsLighting.apply(null, null, 0, "gl_compatibility")
	t.check(true, "uninitialized presentation resources are safe to skip")
	sun.free()

	t.current = "online and local render paths share graphics settings"
	var quality_code: String = (GraphicsQuality as Script).source_code
	t.check(quality_code.contains("GraphicsLighting.apply(sun, env, _level, method)"),
		"the live preset selector applies the lighting policy")
	var atmosphere_code: String = (Atmosphere as Script).source_code
	t.check(atmosphere_code.contains("sun.global_transform.basis.z.normalized()"),
		"visible sun disc aligns with the direction toward the sun, not emitted rays")
	var preview_code: String = (LocalPreview as Script).source_code
	t.check(preview_code.contains("_atmosphere = Atmosphere.new()"),
		"offline preview uses the same sky and sun renderer as multiplayer")
	t.check(preview_code.contains("GraphicsQuality.apply(get_viewport(), _atmosphere, null)"),
		"offline preview receives the saved quality preset")
	t.check(preview_code.contains("Weather.conditions(") and
		preview_code.contains("_weather_next_update = seconds + 0.25"),
		"offline atmosphere samples authoritative weather with bounded CPU cost")
