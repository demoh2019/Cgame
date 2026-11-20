extends RefCounted
## Wind-aligned cloud motion for forest, roads, sky and reflections.
## Pure integrator + shader source assertions; no GPU or downloaded art needed.

const Clouds = preload("res://scripts/client/cloud_shadow_lut.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const Online = preload("res://scripts/client/online_main.gd")
const Offline = preload("res://scripts/client/client_main.gd")


func run(t) -> void:
	t.current = "wind-driven clouds have bounded, continuous physical motion"
	t.eq(Clouds.advance_offset(Vector2(5.0, 9.0), Vector3.ZERO, 0.5),
		Vector2(5.0, 9.0), "calm air holds the clouds in place")
	t.eq(Clouds.advance_offset(Vector2.ZERO, Vector3.ONE, 0.0),
		Vector2.ZERO, "zero elapsed frame does not move cloud cover")
	t.eq(Clouds.advance_offset(Vector2.ZERO, Vector3.ONE, NAN),
		Vector2.ZERO, "bad frame duration cannot move cloud cover")
	t.eq(Clouds.advance_offset(Vector2(2.0, 3.0), Vector3(INF, 0.0, 1.0), 0.1),
		Vector2(2.0, 3.0), "invalid wind cannot poison cloud world coordinates")
	t.eq(Clouds.advance_offset(Vector2(NAN, 0.0), Vector3.ZERO, 0.1),
		Vector2.ZERO, "corrupt accumulated offsets safely reset")

	var east: Vector3 = Vector3(1.0, 0.0, 1.0)
	var one: Vector2 = Clouds.advance_offset(Vector2.ZERO, east, 0.1)
	t.near(one.x, Clouds.MAX_CLOUD_SPEED * 0.1, 0.0001,
		"full-strength east wind moves cloud texture east")
	t.near(one.y, 0.0, 0.0001, "eastward cloud drift has no north component")
	var half: Vector2 = Clouds.advance_offset(Vector2.ZERO,
		Vector3(1.0, 0.0, 0.5), 0.1)
	t.near(half.x, one.x * 0.5, 0.0001,
		"regional wind strength scales cloud drift smoothly")
	t.eq(Clouds.advance_offset(one, Vector3.ZERO, 0.1), one,
		"wind stopping preserves accumulated cloud phase")
	var north: Vector2 = Clouds.advance_offset(Vector2.ZERO,
		Vector3(0.0, -1.0, 1.0), 0.1)
	t.near(north.y, Clouds.TILE_METERS - one.x, 0.0001,
		"negative wind direction wraps instead of creating a texture seam")
	t.near(north.x, 0.0, 0.0001,
		"northward wind does not rotate the cloud field east")
	t.eq(Clouds.advance_offset(Vector2.ZERO, east, 4.0),
		Clouds.advance_offset(Vector2.ZERO, east, 0.25),
		"long frame stalls are clamped to prevent giant cloud jumps")
	var two: Vector2 = Clouds.advance_offset(one, east, 0.1)
	t.check(two.x > one.x, "successive frames continue from prior phase")

	t.current = "cloud UVs remain seamless across 1024m world regions"
	var near_seam: Vector2 = Clouds.advance_offset(
		Vector2(Clouds.TILE_METERS - 0.1, 3.0), east, 0.1)
	t.check(near_seam.x >= 0.0 and near_seam.x < Clouds.TILE_METERS,
		"cloud X offset always remains within one seamless texture period")
	t.check(near_seam.y >= 0.0 and near_seam.y < Clouds.TILE_METERS,
		"cloud Z offset always remains within one seamless texture period")
	var world_point := Vector2(141.3, -87.6)
	var uv: Vector2 = Clouds.wind_uv(world_point, near_seam)
	var adjacent: Vector2 = Clouds.wind_uv(
		world_point + Vector2(Clouds.TILE_METERS, 0.0), near_seam)
	t.near(adjacent.x - uv.x, 1.0, 0.00001,
		"streamed chunk borders have matching texture repetition")
	t.near(adjacent.y - uv.y, 0.0, 0.00001,
		"wrapped texture coordinates preserve perpendicular axis")
	t.eq(Clouds.texture(), Clouds.texture(),
		"wind does not regenerate the original cached R8 cloud lookup")

	t.current = "single GPU global shared by world terrain and foliage"
	t.check(ProjectSettings.has_setting("shader_globals/aa_cloud_shadow_offset"),
		"world-wide wind offset registered before material compilation")
	var setting: Dictionary = ProjectSettings.get_setting(
		"shader_globals/aa_cloud_shadow_offset", {})
	t.eq(str(setting.get("type", "")), "vec2",
		"GPU wind offset is one small vector instead of a texture update")
	var cloud_shader: String = FileAccess.get_file_as_string(
		"res://assets/shaders/cloud_shadow.gdshaderinc")
	t.check(cloud_shader.contains("global uniform vec2 aa_cloud_shadow_offset;"),
		"forest, grass and terrain all read the same weather-driven position")
	t.check(cloud_shader.contains("(world_xz + aa_cloud_shadow_offset) / 1024.0"),
		"surface cloud UVs have world-scale weather-coherent drift")
	t.check(cloud_shader.count("texture(aa_cloud_shadow_map, uv)") == 1,
		"weather motion retains exactly one cached shadow texture sample")
	t.check(cloud_shader.contains("aa_cloud_shadow_strength <= 0.001"),
		"Performance skips the cloud sample entirely")
	t.check(not cloud_shader.contains("sin(") and not cloud_shader.contains("cos("),
		"hot fragment shader evaluates no wind trigonometry")

	t.current = "storm and sunny sky move with the same regional wind"
	var controller: String = (Atmosphere as Script).source_code
	t.check(controller.contains("CloudShadowLut.advance_offset("),
		"wind drives continuous integration instead of directly multiplying TIME")
	t.check(controller.contains("global_shader_parameter_set(&\"aa_cloud_shadow_offset\""),
		"one GPU global updates the existing world shadow texture phase")
	t.check(controller.contains("_wind_publish_seconds >= 0.1"),
		"cloud and plant wind globals are uploaded at no more than ten hertz")
	t.check(controller.contains("set_shader_parameter(\"cloud_wind_rotation\""),
		"panoramic clouds match ground-cloud wind at cached sky refresh")
	var sky_shader: String = FileAccess.get_file_as_string("res://assets/shaders/sky.gdshader")
	t.check(sky_shader.contains("uniform float cloud_wind_rotation"),
		"daytime sky exposes wind-driven panorama rotation")
	t.check(sky_shader.contains("+ cloud_wind_rotation;"),
		"panorama cloud movement no longer uses a fixed unrelated wind")
	t.check(not sky_shader.contains("TIME * drift"),
		"sky radiance still avoids per-frame realtime cubemap invalidation")
	t.check((Online as Script).source_code.contains("Weather.wind_at("),
		"online regional weather reaches atmospheric cloud motion")
	t.check((Offline as Script).source_code.contains("Weather.wind_at("),
		"offline mode uses the same world weather field")
	t.eq(GraphicsQuality.profile(0)["cloud_shadows"], false,
		"existing low-cost Performance mode keeps cloud shadows disabled")
