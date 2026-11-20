extends RefCounted
## GPU-friendly cinematic cirrus shares the world wind-cloud LUT and sky cache.
const VisualProfiles = preload("res://scripts/client/graphics_profiles.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")


func run(t) -> void:
	t.current = "cinematic upper-cloud quality budgets"
	var previous_opacity := -1.0
	for level in 4:
		var profile: Dictionary = VisualProfiles.settings(level)
		var detail: int = int(profile["cirrus_detail"])
		var opacity: float = float(profile["cirrus_opacity"])
		t.check(detail >= 0 and detail <= 2, "cloud LUT sampling tier is bounded")
		t.check(opacity >= 0.0 and opacity <= 0.65, "cirrus opacity stays stable")
		t.check(opacity >= previous_opacity, "cloud fidelity increases with quality")
		previous_opacity = opacity
	t.eq(int(VisualProfiles.settings(0)["cirrus_detail"]), 0,
		"Performance eliminates the entire cloud sampling path")
	t.eq(int(VisualProfiles.settings(3)["cirrus_detail"]), 2,
		"Ultra optionally renders two independent cloud scales")
	t.check(bool(VisualProfiles.settings(1)["sky_use_cached_radiance"]),
		"Balanced samples cirrus when the cached reflection sky updates")
	var low: Dictionary = VisualProfiles.settings(0)
	low["cirrus_detail"] = 2
	t.eq(int(VisualProfiles.settings(0)["cirrus_detail"]), 0,
		"graphics quality data cannot be mutated by callers")

	t.current = "shared cloud LUT sky shader contract"
	var sky_shader := load("res://assets/shaders/sky.gdshader") as Shader
	t.check(sky_shader != null, "cinematic cirrus shader loads")
	if sky_shader == null:
		return
	var code: String = sky_shader.code
	t.check(code.contains("uniform sampler2D cirrus_lut"),
		"upper clouds use the existing filtered R8 texture")
	t.check(code.contains("if (cirrus_detail > 0 && cirrus_opacity > 0.001 && up > 0.08)"),
		"Performance and horizon pixels skip texture work")
	t.check(code.contains("if (cirrus_detail > 1)"),
		"second cloud texture tap only runs on Ultra")
	t.check(code.contains("cirrus_wind_offset / 1024.0"),
		"sky cloud motion uses the same tile period as land shadowing")
	t.check(code.contains("vec3 dark_cloud") and code.contains("cloud_color = mix"),
		"nighttime wisps darken rather than brighten distant stars")
	t.check(code.contains("sun_color * (0.16 * forward_light * daylight)"),
		"daytime upper-cloud highlights follow the directional light")
	t.check(not code.contains("POSITION") and not code.contains("sin(TIME"),
		"no camera-dependent or realtime sky cubemap invalidation")
	t.check(not code.get_slice("void sky() {", 1).contains("return;"),
		"sky() remains legal for Godot's sky shader processor")
	t.check(code.contains("if (use_cached_radiance && !AT_CUBEMAP_PASS)"),
		"new sky layer cannot defeat the low-end cached background")
	t.current = "clouds are wired into the running game"
	var controller: String = (GraphicsQuality as Script).source_code
	var atmosphere: String = (Atmosphere as Script).source_code
	t.check(controller.contains('atmosphere_profile["cirrus_detail"] = world_profile["cirrus_detail"]')
		and controller.contains('atmosphere_profile["cirrus_opacity"] = world_profile["cirrus_opacity"]'),
		"quality selector forwards both sky cloud budgets")
	t.check(atmosphere.contains('set_shader_parameter("cirrus_lut", CloudShadowLut.texture())'),
		"game sky uses the existing terrain-cloud texture instance")
	t.check(atmosphere.contains('set_shader_parameter("cirrus_wind_offset", _cloud_offset)'),
		"clouds update only at the existing radiance refresh cadence")
	t.check(atmosphere.contains('set_shader_parameter("cirrus_detail"')
		and atmosphere.contains('set_shader_parameter("cirrus_opacity"'),
		"quality presets reach the active shader material")
