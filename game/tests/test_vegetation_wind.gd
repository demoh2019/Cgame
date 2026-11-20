extends RefCounted
## GPU wind presentation must be deterministic, bounded and shared by both clients.
const VegetationWind = preload("res://scripts/client/vegetation_wind.gd")
const Foliage = preload("res://scripts/client/foliage.gd")
const GrassField = preload("res://scripts/client/grass_field.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")
const Online = preload("res://scripts/client/online_main.gd")
const Offline = preload("res://scripts/client/client_main.gd")

func run(t) -> void:
	t.current = "one global weather wind shared by grass and foliage"
	t.check(ProjectSettings.has_setting("shader_globals/aa_vegetation_wind"), "wind vector is registered")
	var setting: Dictionary = ProjectSettings.get_setting("shader_globals/aa_vegetation_wind", {})
	t.eq(str(setting.get("type", "")), "vec3", "one vec3 holds direction and strength")
	t.check(Foliage.SHADER_CODE.contains("global uniform vec3 aa_vegetation_wind"), "trees respond to GPU wind")
	t.check(GrassField.SHADER_CODE.contains("global uniform vec3 aa_vegetation_wind"), "grass responds to GPU wind")
	t.check(Foliage.SHADER_CODE.contains("aa_vegetation_wind.z"), "tree movement uses weather strength")
	t.check(GrassField.SHADER_CODE.contains("aa_vegetation_wind.z"), "grass movement uses weather strength")
	t.current = "finite, normalized and clamped regional wind"
	t.eq(VegetationWind.target(Vector2.ZERO), Vector3.ZERO, "sheltered areas remain still")
	t.eq(VegetationWind.target(Vector2(INF, 0.0)), Vector3.ZERO, "invalid winds cannot reach the GPU")
	var east: Vector3 = VegetationWind.target(Vector2(1.5, 0.0))
	t.near(east.x, 1.0, 0.0001, "east wind points east")
	t.near(east.y, 0.0, 0.0001, "east wind has no z movement")
	t.near(east.z, 1.0, 0.0001, "strong wind reaches full motion")
	var north: Vector3 = VegetationWind.target(Vector2(0.0, -0.3))
	t.near(north.y, -1.0, 0.0001, "negative z wind bends north")
	t.near(north.z, 0.2, 0.0001, "light breeze keeps subtle movement")
	t.near(VegetationWind.target(Vector2(100, 0)).z, 1.0, 0.0001, "extreme gusts are bounded")
	t.current = "wind blends smoothly across weather cells"
	t.eq(VegetationWind.smooth(Vector3.ZERO, east, 0.0), Vector3.ZERO, "paused simulation does not animate")
	t.eq(VegetationWind.smooth(Vector3.ZERO, east, NAN), Vector3.ZERO, "bad frame duration is ignored")
	var first: Vector3 = VegetationWind.smooth(Vector3.ZERO, east, 0.1)
	t.check(first.z > 0.0 and first.z < 1.0, "wind fades in instead of snapping")
	t.check(VegetationWind.smooth(first, east, 0.1).z > first.z, "blend converges over time")
	t.near(VegetationWind.smooth(Vector3.ZERO, east, 10.0).z,
		VegetationWind.smooth(Vector3.ZERO, east, 0.25).z, 0.0001, "long frame stalls are clamped")
	t.check(VegetationWind.smooth(east, Vector3.ZERO, 0.1).z < east.z, "wind fades out when sheltered")
	t.current = "the live and local render paths share the same weather source"
	t.check((Atmosphere as Script).source_code.contains("global_shader_parameter_set(&\"aa_vegetation_wind\""),
		"atmosphere publishes the one global wind parameter")
	t.check((Online as Script).source_code.contains("Weather.wind_at("),
		"online client reads deterministic regional wind")
	t.check((Offline as Script).source_code.contains("Weather.wind_at("),
		"offline client uses identical world weather")
