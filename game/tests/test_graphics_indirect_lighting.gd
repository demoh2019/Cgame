extends RefCounted
## Renderer-aware SSAO and indirect lighting budgets with actual Godot resources.
const Indirect = preload("res://scripts/client/graphics_indirect_lighting.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "half-resolution screen-space lighting tiers"
	t.eq(Indirect.settings(-1, "forward_plus"), Indirect.settings(0, "forward_plus"),
		"negative quality tier safely clamps")
	t.eq(Indirect.settings(100, "forward_plus"), Indirect.settings(3, "forward_plus"),
		"out-of-range quality tier safely clamps")
	for method in ["gl_compatibility", "mobile", ""]:
		for tier in 4:
			var p: Dictionary = Indirect.settings(tier, method)
			t.check(not p["ssao_enabled"] and not p["ssil_enabled"],
				"unsupported renderer never enables expensive screen-space passes")
	for tier in [0, 1]:
		var p: Dictionary = Indirect.settings(tier, "forward_plus")
		t.check(not p["ssao_enabled"] and not p["ssil_enabled"],
			"Performance and Balanced stay free of contact and bounce passes")
	var high: Dictionary = Indirect.settings(2, "forward_plus")
	var ultra: Dictionary = Indirect.settings(3, "forward_plus")
	t.check(bool(high["ssao_enabled"]) and not bool(high["ssil_enabled"]),
		"High uses only bounded contact shadows")
	t.check(bool(ultra["ssao_enabled"]) and bool(ultra["ssil_enabled"]),
		"Ultra enables both AO and nearby color bounce")
	t.check(float(ultra["ssao_intensity"]) <= 1.5,
		"cinematic AO does not crush ambient light under vegetation")
	t.check(float(ultra["ssil_radius"]) < 3.0,
		"short SSIL rays limit edge leaking and undersampling")
	t.eq(float(ultra["ssil_normal_rejection"]), 1.0,
		"unseen back-facing surfaces cannot bleed bounce light")
	t.eq(float(ultra["ssao_light_affect"]), 0.0,
		"AO never fakes direct sun and lantern occlusion")
	var env := Environment.new()
	Indirect.apply(env, 3, "forward_plus")
	t.check(env.ssao_enabled and env.ssil_enabled,
		"Ultra flags are applied to the actual Godot Environment")
	t.near(env.ssao_radius, float(ultra["ssao_radius"]), 0.0001,
		"fine contact AO radius is applied")
	t.near(env.ssil_radius, float(ultra["ssil_radius"]), 0.0001,
		"short bounce radius is applied")
	t.near(env.ssil_intensity, float(ultra["ssil_intensity"]), 0.0001,
		"indirect light strength is applied")
	Indirect.apply(env, 2, "forward_plus")
	t.check(env.ssao_enabled and not env.ssil_enabled,
		"live Ultra-to-High change frees diffuse bounce pass")
	Indirect.apply(env, 3, "gl_compatibility")
	t.check(not env.ssao_enabled and not env.ssil_enabled,
		"renderer fallback switches off unsupported buffers")
	Indirect.apply(env, 3, "mobile")
	t.check(not env.ssao_enabled and not env.ssil_enabled,
		"mobile never enables Forward+ effects")
	t.check(GraphicsQuality.profile(3)["ssil"],
		"Ultra's user-facing preset still matches the indirect-light budget")
