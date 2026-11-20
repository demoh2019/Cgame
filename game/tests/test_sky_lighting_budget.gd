extends RefCounted
## Sky cubemap refreshes are decoupled from frame time and light movement.
## The sky shader is source-checked because this regression otherwise silently re-enables realtime radiance.

const VisualProfiles = preload("res://scripts/client/graphics_profiles.gd")


func run(t) -> void:
	t.current = "sky reflection update budgets"
	var low: float = float(VisualProfiles.settings(0)["sky_refresh_interval"])
	var balanced: float = float(VisualProfiles.settings(1)["sky_refresh_interval"])
	var high: float = float(VisualProfiles.settings(2)["sky_refresh_interval"])
	var ultra: float = float(VisualProfiles.settings(3)["sky_refresh_interval"])
	t.check(low > balanced and balanced > high and high > ultra,
		"higher graphics tiers refresh reflections more often")
	t.check(ultra >= 0.12, "even Ultra bounds reflection recomputes")
	t.check(low <= 2.0, "Performance refreshes sky reflections periodically")

	t.current = "sky radiance dependency contract"
	var source: String = FileAccess.get_file_as_string("res://assets/shaders/sky.gdshader")
	t.check(not source.is_empty(), "sky shader must exist")
	t.check(source.contains("uniform float sky_time"), "sky animation is driven by cached time")
	t.check(source.contains("uniform vec3 sun_direction"), "sky sun direction is cached")
	t.check(not source.contains("TIME * drift"), "animated panoramas cannot force per-frame radiance updates")
	t.check(not source.contains("sin(TIME"), "star animation cannot force per-frame radiance updates")
	t.check(not source.contains("LIGHT0_DIRECTION"), "moving directional lights cannot directly invalidate sky radiance")
	t.check(not source.contains("LIGHT0_COLOR"), "moving directional light colors cannot directly invalidate sky radiance")


	t.current = "Godot radiance background reuse scales with device tier"
	var p0: Dictionary = VisualProfiles.settings(0)
	var p1: Dictionary = VisualProfiles.settings(1)
	var p2: Dictionary = VisualProfiles.settings(2)
	var p3: Dictionary = VisualProfiles.settings(3)
	t.check(bool(p0["sky_use_cached_radiance"]),
		"Performance reuses the periodically refreshed sky radiance")
	t.check(bool(p1["sky_use_cached_radiance"]),
		"Balanced avoids per-screen-pixel sky panorama and stars")
	t.check(not bool(p2["sky_use_cached_radiance"]),
		"High retains full-resolution panorama and precise stars")
	t.check(not bool(p3["sky_use_cached_radiance"]),
		"Ultra renders full-resolution atmospheric background")
	var sky_source: String = FileAccess.get_file_as_string("res://assets/shaders/sky.gdshader")
	t.check(sky_source.contains("if (use_cached_radiance && !AT_CUBEMAP_PASS)"),
		"radiance sampling is never performed during cubemap generation")
	t.check(sky_source.contains("texture(RADIANCE, dir).rgb"),
		"sky cache uses Godot's supported built-in cubemap sampler")
	var sky_fragment: String = sky_source.get_slice("void sky() {", 1)
	t.check(not sky_fragment.contains("return;"),
		"Godot sky() processor cannot use return, even for the cached-radiance fast path")
	t.check(sky_source.contains("} else {\n\t\tfloat up = dir.y;"),
		"expensive procedural sky only evaluates on the uncached path")
	t.check(sky_source.contains("if (has_panorama && daylight > 0.005)"),
		"night skips expensive daytime spherical panorama lookup")
	t.check(sky_source.contains("SKY_COORDS * vec2(480.0, 240.0)"),
		"stars are placed in a stable panoramic sky coordinate system")
	t.check(sky_source.contains("fwidth(star_uv)") and
		sky_source.contains("point_star"),
		"full quality stars use antialiased discs instead of noisy square cells")
	t.check(sky_source.contains("if (daylight < 0.95 && up > 0.02 && storm < 0.98)"),
		"day and storm sky skip procedural star hashes and twinkling")
	var atmosphere_script: Script = load("res://scripts/client/atmosphere.gd") as Script
	t.check(atmosphere_script != null, "sky rendering controller loads")
	if atmosphere_script != null:
		t.check(atmosphere_script.source_code.contains(
			'set_shader_parameter("use_cached_radiance"'),
			"quality selector actually controls the sky shader fast path")
