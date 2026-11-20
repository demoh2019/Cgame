extends RefCounted
## Renderer-specific SSR budget. No GPU required: Godot Environment exposes
## the actual SSR properties even when tests run headless.

const GraphicsReflections = preload("res://scripts/client/graphics_reflections.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "renderer-aware reflections"
	var performance: Dictionary = GraphicsReflections.settings(0, "forward_plus")
	var balanced: Dictionary = GraphicsReflections.settings(1, "forward_plus")
	var high: Dictionary = GraphicsReflections.settings(2, "forward_plus")
	var ultra: Dictionary = GraphicsReflections.settings(3, "forward_plus")
	t.check(not performance["enabled"], "Performance skips the full-screen reflection ray pass")
	t.check(not balanced["enabled"], "Balanced skips the full-screen reflection ray pass")
	t.check(high["enabled"] and ultra["enabled"], "High/Ultra enable SSR on Forward+")
	t.check(int(high["max_steps"]) < int(ultra["max_steps"]), "Ultra traces longer reflections than High")
	t.eq(int(high["roughness_quality"]), RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_MEDIUM,
		"High uses mid-cost native roughness-aware reflection reconstruction")
	t.eq(int(ultra["roughness_quality"]), RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_HIGH,
		"Ultra uses native high-quality glossy reflection mip filtering")
	t.eq(int(performance["roughness_quality"]), RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_DISABLED,
		"Performance avoids all SSR roughness-filter GPU work")
	t.eq(int(balanced["roughness_quality"]), RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_DISABLED,
		"Balanced avoids all SSR roughness-filter GPU work")
	t.check(int(high["max_steps"]) <= 32 and int(ultra["max_steps"]) <= 48,
		"reflection rays have an explicit performance ceiling")
	t.check(float(ultra["depth_tolerance"]) < float(high["depth_tolerance"]),
		"Ultra rejects less precise glossy ray hits than High")
	t.check(float(ultra["depth_tolerance"]) > 0.0,
		"reflection depth tolerance cannot collapse to zero")
	t.eq(float(high["depth_tolerance"]), 0.24,
		"High retains forgiving but bounded hit depth near geometry borders")
	for method in ["gl_compatibility", "mobile"]:
		for tier in 4:
			t.check(not bool(GraphicsReflections.settings(tier, method)["enabled"]),
				"unsupported renderer %s never enables SSR tier %d" % [method, tier])
	t.eq(GraphicsReflections.settings(-100, "forward_plus"),
		GraphicsReflections.settings(0, "forward_plus"), "negative quality clamps")
	t.eq(GraphicsReflections.settings(100, "forward_plus"),
		GraphicsReflections.settings(3, "forward_plus"), "oversized quality clamps")
	t.check(float(high["fade_in"]) >= 0.0 and float(high["fade_out"]) >= 0.0,
		"ray march fades soften contact and distance cutoffs")

	t.current = "actual world environment SSR controls"
	var env := Environment.new()
	GraphicsReflections.apply(env, 3, "forward_plus")
	t.check(env.ssr_enabled, "Ultra enables screen-space reflections in Environment")
	t.eq(GraphicsReflections._last_roughness_quality, RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_HIGH,
		"real renderer is configured for Ultra rough-surface reconstruction")
	t.eq(env.ssr_max_steps, 48, "Ultra caps the real Godot SSR ray steps")
	t.near(env.ssr_depth_tolerance, 0.20, 0.001,
		"Ultra uses tighter hit depth confidence after subpixel-centred SSR resolve")
	GraphicsReflections.apply(env, 2, "forward_plus")
	t.eq(env.ssr_max_steps, 28, "High reduces SSR GPU cost without replacing the Environment")
	t.near(env.ssr_depth_tolerance, 0.24, 0.001,
		"High updates native depth confidence without changing trace cost")
	t.eq(GraphicsReflections._last_roughness_quality, RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_MEDIUM,
		"native reflection mip quality follows live High profile")
	GraphicsReflections.apply(env, 0, "forward_plus")
	t.check(not env.ssr_enabled, "selecting Performance releases SSR GPU work")
	t.eq(GraphicsReflections._last_roughness_quality, RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_DISABLED,
		"native renderer disables roughness filtering when SSR is off")
	GraphicsReflections.apply(env, 3, "gl_compatibility")
	t.check(not env.ssr_enabled, "renderer fallback clears stale SSR state")
	t.eq(GraphicsReflections._last_roughness_quality, RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_DISABLED,
		"Compatibility prevents stale native roughness filtering")
	GraphicsReflections.apply(null, 3, "forward_plus")
	t.check(true, "offline preview may apply quality before its environment exists")

	t.current = "reflection integration and fallback"
	t.check(ProjectSettings.get_setting("rendering/environment/screen_space_reflection/half_size", false),
		"SSR renders at half resolution instead of adding a full-size ray pass")
	t.check(int(high["max_steps"]) == 28 and int(ultra["max_steps"]) == 48,
		"higher-quality edge reconstruction never adds expensive ray steps")
	var graphics_script: Script = GraphicsQuality as Script
	t.check(RenderingServer.has_method("environment_set_ssr_roughness_quality"),
		"engine exposes native SSR roughness filtering to GDScript")
	t.check((GraphicsReflections as Script).source_code.contains(
		"RenderingServer.environment_set_ssr_roughness_quality(roughness_quality)"),
		"native engine SSR roughness filter is actually called on tier changes")
	t.check((GraphicsReflections as Script).source_code.contains(
		"if environment.ssr_enabled != enabled:"),
		"shared live graphics controller skips unchanged native SSR state")
	t.check((GraphicsReflections as Script).source_code.contains(
		"if not is_equal_approx(environment.ssr_fade_out, fade_out):"),
		"native reflection fade is not resent every frame")
	t.check(graphics_script.source_code.contains("GraphicsReflections.apply(env, _level, method)"),
		"the actual graphics selector shares SSR policy with live and local scenes")
	var atmosphere := load("res://scripts/client/atmosphere.gd") as Script
	t.check(atmosphere != null, "the sky reflection controller is loadable")
	if atmosphere != null:
		t.check(atmosphere.source_code.contains("Environment.REFLECTION_SOURCE_SKY"),
			"SSR has existing sky/reflection radiance for off-screen surfaces")


	t.current = "guarded SSR rays and idempotent native quality updates"
	var checked_env := Environment.new()
	GraphicsReflections.apply(checked_env, 3, "forward_plus")
	var previous_state: Array = [
		checked_env.ssr_enabled, checked_env.ssr_max_steps,
		checked_env.ssr_fade_in, checked_env.ssr_fade_out,
		checked_env.ssr_depth_tolerance]
	GraphicsReflections.apply(checked_env, 3, "forward_plus")
	t.eq([
		checked_env.ssr_enabled, checked_env.ssr_max_steps,
		checked_env.ssr_fade_in, checked_env.ssr_fade_out,
		checked_env.ssr_depth_tolerance], previous_state,
		"re-applying Ultra preserves all native reflection settings")
	GraphicsReflections.apply(checked_env, 1, "forward_plus")
	t.check(not checked_env.ssr_enabled,
		"Balanced immediately disables the expensive ray pass")
	GraphicsReflections.apply(checked_env, 2, "forward_plus")
	t.check(checked_env.ssr_enabled and checked_env.ssr_max_steps == 28,
		"switching to High retains 28 protected SSR steps")
	var reflection_code: String = (GraphicsReflections as Script).source_code
	t.check(reflection_code.contains("if environment.ssr_enabled != enabled:"),
		"identical enable state never triggers duplicate native updates")
	t.check(reflection_code.contains("if environment.ssr_max_steps != steps:")
		and reflection_code.contains(
			"if not is_equal_approx(environment.ssr_depth_tolerance, tolerance):"),
		"unchanged ray length and tolerance never trigger duplicate setters")
