extends RefCounted
## GPU wind presentation must be deterministic, bounded and shared by both clients.
const VegetationWind = preload("res://scripts/client/vegetation_wind.gd")
const Foliage = preload("res://scripts/client/foliage.gd")
const GrassField = preload("res://scripts/client/grass_field.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")
const Online = preload("res://scripts/client/online_main.gd")
const Offline = preload("res://scripts/client/client_main.gd")
const VisualProfiles = preload("res://scripts/client/graphics_profiles.gd")

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


	t.current = "world-space wind is invariant under instanced rotation and scale"
	var include_code: String = FileAccess.get_file_as_string(
		"res://assets/shaders/vegetation_wind_space.gdshaderinc")
	t.check(include_code.contains("vec2 aa_wind_world_to_local_xz("),
		"one shared shader implementation converts world wind to local vertices")
	t.check(include_code.contains("dot(world_vector, local_x_axis)")
		and include_code.contains("dot(world_vector, local_z_axis)"),
		"basis projection uses both instance axes, never local movement as world wind")
	t.check(include_code.contains("max(dot(local_x_axis, local_x_axis), 0.0001)"),
		"nonuniform scaling and zero-scale instances remain bounded")
	t.check(Foliage.SHADER_CODE.contains("vegetation_wind_space.gdshaderinc")
		and GrassField.SHADER_CODE.contains("vegetation_wind_space.gdshaderinc"),
		"tree and grass reuse identical rotation/scale correction")
	t.check(Foliage.SHADER_CODE.contains("aa_wind_world_to_local_xz(motion * amount, MODEL_MATRIX)"),
		"tree gust displacement follows the actual world wind on rotated assets")
	t.check(GrassField.SHADER_CODE.contains("aa_wind_world_to_local_xz(world_bend, MODEL_MATRIX)"),
		"per-tuft MultiMesh yaw and size cannot rotate the world breeze")
	for angle in [0.0, 0.45, 1.57, -1.1, 3.14]:
		for scale in [Vector3.ONE, Vector3(2.0, 1.0, 0.6), Vector3(0.6, 1.0, 1.7)]:
			var basis := Basis(Vector3.UP, angle).scaled(scale)
			for wind in [Vector2(0.1, 0.0), Vector2(0.0, -0.25), Vector2(0.3, 0.15)]:
				var world_vector := Vector3(wind.x, 0.0, wind.y)
				var bx: Vector3 = basis.x
				var bz: Vector3 = basis.z
				var local_x: float = world_vector.dot(bx) / maxf(bx.length_squared(), 0.0001)
				var local_z: float = world_vector.dot(bz) / maxf(bz.length_squared(), 0.0001)
				var reconstructed: Vector3 = basis * Vector3(local_x, 0.0, local_z)
				t.near(reconstructed.x, wind.x, 0.0001,
					"horizontal motion remains world-aligned across yaws and instance scales")
				t.near(reconstructed.z, wind.y, 0.0001,
					"the secondary world axis stays aligned after local-space reconstruction")
	t.current = "calm foliage skips vertex wave work; graphics presets scale sunlit normals"
	t.check(Foliage.SHADER_CODE.contains("if (wind_power > 0.001) {")
		and GrassField.SHADER_CODE.contains("if (wind_power > 0.001) {"),
		"quiet weather branches before wave trigonometry on both GPU shaders")
	t.check(GrassField.SHADER_CODE.contains("varying vec3 aa_world_grass_normal;")
		and GrassField.SHADER_CODE.contains("NORMAL = normalize((VIEW_MATRIX * vec4(aa_world_grass_normal, 0.0)).xyz);"),
		"grass tips adjust PBR normal direction without a lighting texture or pass")
	t.check(ProjectSettings.has_setting("shader_globals/aa_grass_normal_wind"),
		"new GPU normal quality control exists before compilation")
	var last_normal := -1.0
	for level in 4:
		var visual: Dictionary = VisualProfiles.settings(level)
		var bend: float = float(visual.get("grass_normal_wind", -1.0))
		t.check(bend >= 0.0 and bend <= 0.9,
			"normal sway cost remains bounded at every detail preset")
		t.check(bend >= last_normal,
			"higher tier preserves at least as much moving grass light detail")
		last_normal = bend
	t.eq(float(VisualProfiles.settings(0)["grass_normal_wind"]), 0.0,
		"Performance stays on static upward-facing grass normals")
	t.check((load("res://scripts/client/graphics_quality.gd") as Script).source_code.contains(
		'global_shader_parameter_set(&"aa_grass_normal_wind"'),
		"preset changes update one shared grass-normal GPU parameter")
