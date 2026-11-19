extends SceneTree
## Water System headless integration tests. Nonzero exit on failures.
## godot --headless --path misc/water_system --script res://tests/test_water_system.gd

const Wave := preload("res://addons/water_system/water_wave.gd")
const Profile := preload("res://addons/water_system/water_profile.gd")
const Surface := preload("res://addons/water_system/water_surface_3d.gd")
const Buoyancy := preload("res://addons/water_system/water_buoyancy_3d.gd")

var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run_all")


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("Water System FAIL: %s" % message)


func _approximately(a: float, b: float, tolerance: float = 0.0001) -> bool:
	return absf(a - b) <= tolerance


func _single_wave_profile(amplitude: float = 2.0) -> WaterProfile:
	var profile := Profile.new()
	var wave := Wave.new()
	wave.amplitude = amplitude
	wave.wavelength = 4.0
	wave.angular_speed = 0.0
	wave.direction = Vector2(1, 0)
	wave.phase = 0.0
	profile.waves.append(wave)
	return profile


func _invalid(profile: WaterProfile, message: String) -> void:
	_check(not profile.validation_error().is_empty(), message + " rejects invalid profile")
	var result := profile.sample(Vector2.ZERO, 0.0)
	_check(not result["ok"] and not result["error"].is_empty(),
			message + " returns structured validation error")


func _test_calculated_heights() -> void:
	var profile := _single_wave_profile()
	_check(profile.validation_error().is_empty(), "valid analytic wave")
	_check(_approximately(profile.sample(Vector2.ZERO, 0)["height"], 0.0), "height at origin")
	_check(_approximately(profile.sample(Vector2(1, 0), 0)["height"], 2.0), "positive peak")
	_check(_approximately(profile.sample(Vector2(2, 0), 0)["height"], 0.0), "second zero")
	_check(_approximately(profile.sample(Vector2(3, 0), 0)["height"], -2.0), "negative trough")
	_check(_approximately(profile.sample(Vector2(5, 0), 0)["height"], 2.0), "spatial period")
	_check(_approximately(profile.sample(Vector2(-3, 0), 0)["height"], 2.0), "negative coordinates")
	_check(profile.sample(Vector2(1, 9), 0)["height"] == profile.sample(Vector2(1, 0), 0)["height"],
			"X-direction wave is invariant over Z")


func _test_analytic_normals() -> void:
	var profile := _single_wave_profile()
	var crest := profile.sample(Vector2(1, 0), 0)
	_check(crest["ok"], "crest sample succeeds")
	_check(crest["normal"].is_equal_approx(Vector3.UP), "normal upright at crest")
	var zero_crossing := profile.sample(Vector2.ZERO, 0)
	var expected := Vector3(-PI, 1, 0).normalized()
	_check(zero_crossing["normal"].is_equal_approx(expected), "normal equals analytic derivative")
	for location in [Vector2(-20, 3), Vector2(0, 0), Vector2(4.75, -7)]:
		var normal: Vector3 = profile.sample(location, 0)["normal"]
		_check(_approximately(normal.length(), 1.0), "normal has unit length")
		_check(normal.y > 0.0, "water surface normal always points upward")


func _test_time_dependence() -> void:
	var profile := _single_wave_profile()
	profile.waves[0].angular_speed = 2.0
	var at_zero: float = profile.sample(Vector2.ZERO, 0.0)["height"]
	var at_quarter: float = profile.sample(Vector2.ZERO, PI / 4.0)["height"]
	_check(_approximately(at_zero, 0.0), "time zero starts at zero displacement")
	_check(_approximately(at_quarter, -2.0), "phase advances at angular speed")
	_check(_approximately(profile.sample(Vector2.ZERO, PI)["height"], at_zero),
			"time-periodic phase")
	_check(_approximately(profile.sample(Vector2(2, 0), -PI)["height"],
			profile.sample(Vector2(2, 0), PI)["height"]), "negative time is deterministic")


func _test_multiple_waves_and_cancellation() -> void:
	var profile := _single_wave_profile(1.5)
	var opposite := Wave.new()
	opposite.direction = Vector2(1, 0)
	opposite.wavelength = 4
	opposite.amplitude = 1.5
	opposite.angular_speed = 0
	opposite.phase = PI
	profile.waves.append(opposite)
	for x in [-5.2, -1.0, 0.25, 3.1, 9.0]:
		var sample := profile.sample(Vector2(x, 0), 2)
		_check(sample["ok"], "valid multiwave sample")
		_check(_approximately(sample["height"], 0), "out-of-phase waves cancel")
		_check(sample["normal"].is_equal_approx(Vector3.UP), "slope cancellation restores flat normal")


func _test_empty_and_default_profiles() -> void:
	var calm := Profile.new()
	_check(calm.validation_error().is_empty(), "zero waves is valid calm water")
	for p in [Vector2.ZERO, Vector2(9000, -9000)]:
		var result := calm.sample(p, 50)
		_check(result["ok"], "calm water samples")
		_check(result["height"] == 0.0, "calm water zero elevation")
		_check(result["normal"] == Vector3.UP, "calm water upward normal")
	var defaults := Profile.make_default()
	_check(defaults.waves.size() == 3, "default profile has three waves")
	_check(defaults.validation_error().is_empty(), "default profile valid")
	_check(defaults.sample(Vector2(2, 5), 3)["ok"], "default profile evaluates")
	_check(defaults.sample(Vector2(2, 5), 3)["height"] ==
			defaults.sample(Vector2(2, 5), 3)["height"], "default profile deterministic")


func _test_direction_normalization() -> void:
	var profile := _single_wave_profile()
	var original: float = profile.sample(Vector2(0.6, 0.8), 0)["height"]
	profile.waves[0].direction = Vector2(5, 0)
	_check(_approximately(original, profile.sample(Vector2(0.6, 0.8), 0)["height"]),
			"direction magnitude is ignored")
	profile.waves[0].direction = Vector2(-1, 0)
	_check(_approximately(profile.sample(Vector2(1, 0), 0)["height"], -2.0),
			"reversed direction reverses phase in space")


func _test_validation() -> void:
	var profile := _single_wave_profile()
	profile.waves[0].amplitude = -1
	_invalid(profile, "negative amplitude")
	profile.waves[0].amplitude = NAN
	_invalid(profile, "NaN amplitude")
	profile.waves[0].amplitude = 1
	profile.waves[0].wavelength = 0
	_invalid(profile, "zero wavelength")
	profile.waves[0].wavelength = INF
	_invalid(profile, "infinite wavelength")
	profile.waves[0].wavelength = 4
	profile.waves[0].direction = Vector2.ZERO
	_invalid(profile, "zero direction")
	profile.waves[0].direction = Vector2(NAN, 0)
	_invalid(profile, "NaN direction")
	profile.waves[0].direction = Vector2.RIGHT
	profile.waves[0].angular_speed = INF
	_invalid(profile, "infinite speed")
	profile.waves[0].angular_speed = 0
	profile.waves[0].phase = NAN
	_invalid(profile, "NaN phase")
	profile.waves[0].phase = 0
	profile.waves.append(null)
	_invalid(profile, "null wave")
	profile.waves.pop_back()
	for i in 4:
		profile.waves.append(Wave.new())
	_invalid(profile, "more than four waves")


func _test_invalid_sampling_coordinates() -> void:
	var profile := _single_wave_profile()
	for position in [Vector2(NAN, 0), Vector2(INF, 0), Vector2(0, -INF)]:
		_check(not profile.sample(position, 0)["ok"], "nonfinite position rejected")
	for seconds in [INF, -INF, NAN]:
		_check(not profile.sample(Vector2.ZERO, seconds)["ok"], "nonfinite time rejected")


func _test_uniform_packing() -> void:
	var profile := _single_wave_profile()
	var packed := profile.wave_parameters(0)
	_check(packed["wave"] is Vector4, "GPU packing is a Vector4")
	_check(packed["motion"] is Vector2, "GPU motion packing is a Vector2")
	_check(_approximately(packed["wave"].z, 2.0), "GPU amplitude matches CPU")
	_check(_approximately(packed["wave"].w, 4.0), "GPU wavelength matches CPU")
	_check(_approximately(packed["motion"].x, 0.0), "GPU angular velocity matches CPU")
	for index in [1, 2, 3, 4, -1]:
		var empty := profile.wave_parameters(index)
		_check(empty["wave"].z == 0.0, "unused/invalid GPU slot has zero amplitude")


func _test_water_surface_generation() -> void:
	var water: WaterSurface3D = Surface.new()
	root.add_child(water)
	_check(water.wave_profile != null, "water auto-instantiates a default profile")
	_check(water.mesh is PlaneMesh, "water auto-creates PlaneMesh")
	_check(water.material_override is ShaderMaterial, "water attaches a ShaderMaterial")
	_check(water.surface_size == Vector2(64, 64), "initial surface size")
	water.surface_size = Vector2(8, 6)
	water.subdivisions = 4
	_check(water.rebuild_surface(), "valid mesh rebuild")
	_check((water.mesh as PlaneMesh).size == Vector2(8, 6), "mesh size updated")
	_check((water.mesh as PlaneMesh).subdivide_width == 4, "horizontal subdivisions updated")
	_check((water.mesh as PlaneMesh).subdivide_depth == 4, "depth subdivisions updated")
	var old_mesh: Mesh = water.mesh
	water.surface_size = Vector2(-1, 3)
	_check(not water.rebuild_surface(), "invalid plane dimensions rejected")
	_check(water.mesh == old_mesh, "invalid mesh parameters preserve last good plane")
	water.surface_size = Vector2(8, 6)
	water.subdivisions = 129
	_check(not water.rebuild_surface(), "excessive subdivisions rejected")
	water.queue_free()


func _test_surface_sampling_and_time() -> void:
	var water: WaterSurface3D = Surface.new()
	water.wave_profile = _single_wave_profile()
	water.position = Vector3(0, 17, 0)
	root.add_child(water)
	_check(water.set_simulation_time(0), "set time zero")
	var high := water.sample_at(Vector3(1, -100, 0))
	_check(high["ok"], "sample world position")
	_check(_approximately(high["height"], 19.0), "water translates local height into world Y")
	_check(high["normal"].is_equal_approx(Vector3.UP), "normal unaffected by vertical translation")
	_check(water.set_simulation_time(-2.0), "negative simulation time allowed")
	_check(_approximately(water.get_simulation_time(), -2.0), "time query matches setter")
	_check(not water.set_simulation_time(INF), "infinite simulation time rejected")
	_check(not water.set_simulation_time(NAN), "NaN simulation time rejected")
	_check(not water.sample_at(Vector3(NAN, 0, 0))["ok"], "nonfinite world position rejected")
	_check(not water.sample_at(Vector3(1000, 0, 0))["ok"], "sample beyond finite water area rejected")
	_check(not water.sample_at(Vector3(0, 0, 1000))["ok"], "outside water Z bounds rejected")
	_check(water.sample_at(Vector3(32, 0, 0))["ok"], "edge of water plane is inclusive")
	_check(_approximately(water.sample_at(Vector3(1, 0, 0), 0.0)["height"], 19.0),
			"explicit time override works")
	water.queue_free()


func _test_shader_parameters() -> void:
	var water: WaterSurface3D = Surface.new()
	water.wave_profile = _single_wave_profile()
	water.water_tint = Color(0.1, 0.2, 0.3, 1.0)
	water.water_opacity = 0.65
	root.add_child(water)
	_check(water.set_simulation_time(4.25), "material update succeeds")
	var material := water.material_override as ShaderMaterial
	var params := water.wave_profile.wave_parameters(0)
	_check(material != null, "shader material available")
	if material != null:
		_check(material.get_shader_parameter("wave_0") == params["wave"],
				"shader receives CPU wave parameters")
		_check(material.get_shader_parameter("motion_0") == params["motion"],
				"shader receives CPU wave motion")
		_check(_approximately(material.get_shader_parameter("water_time"), 4.25),
				"shader time matches CPU time")
		_check(_approximately(material.get_shader_parameter("water_opacity"), 0.65),
				"shader opacity matches node")
		_check(material.get_shader_parameter("water_tint") == water.water_tint,
				"shader tint matches node")
		_check(material.get_shader_parameter("wave_3").z == 0.0,
				"unused wave uniforms are disabled")
	water.queue_free()


func _test_wave_resource_save_load() -> void:
	var profile := Profile.make_default()
	var path := "user://water_profile_test.tres"
	_check(ResourceSaver.save(profile, path) == OK, "serialize wave profile")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as WaterProfile
	_check(loaded != null, "deserialize custom WaterProfile resource")
	if loaded != null:
		_check(loaded.waves.size() == profile.waves.size(), "all waves preserved")
		for position in [Vector2.ZERO, Vector2(10, 11), Vector2(-7, 20)]:
			var before := profile.sample(position, 5)
			var after := loaded.sample(position, 5)
			_check(_approximately(before["height"], after["height"]),
					"reloaded waves produce same heights")
			_check(before["normal"].is_equal_approx(after["normal"]),
					"reloaded waves produce same normals")


func _test_buoyancy_lift() -> void:
	var buoy: WaterBuoyancy3D = Buoyancy.new()
	buoy.lift_per_meter = 10
	buoy.max_submergence = 2
	buoy.water_drag = 4
	_check(buoy.compute_point_force(Vector3(0, 1, 0), 0, Vector3.ZERO) == Vector3.ZERO,
			"dry point has no buoyancy")
	_check(buoy.compute_point_force(Vector3.ZERO, 1, Vector3.ZERO) == Vector3(0, 10, 0),
			"one meter immersion gives specified lift")
	_check(buoy.compute_point_force(Vector3.ZERO, 3, Vector3.ZERO) == Vector3(0, 20, 0),
			"max submergence caps lift")
	_check(buoy.compute_point_force(Vector3.ZERO, 1, Vector3(1, 0, 0)) == Vector3(-2, 10, 0),
			"drag opposes lateral motion at half submergence")
	_check(buoy.compute_point_force(Vector3.ZERO, 1, Vector3(0, 2, 0)) == Vector3(0, 6, 0),
			"drag opposes vertical motion")
	_check(buoy.compute_point_force(Vector3.ZERO, 0, Vector3.ZERO) == Vector3.ZERO,
			"surface contact without immersion has no force")
	_check(buoy.sample_points.size() == 4, "four default buoyancy float points")
	buoy.queue_free()


func _test_invalid_buoyancy() -> void:
	var buoy: WaterBuoyancy3D = Buoyancy.new()
	for value in [-1.0, NAN, INF]:
		buoy.lift_per_meter = value
		_check(buoy.compute_point_force(Vector3.ZERO, 1, Vector3.ZERO) == Vector3.ZERO,
				"invalid buoyancy lift rejected")
	buoy.lift_per_meter = 10
	for value in [0.0, -1.0, NAN]:
		buoy.max_submergence = value
		_check(buoy.compute_point_force(Vector3.ZERO, 1, Vector3.ZERO) == Vector3.ZERO,
				"invalid depth cap rejected")
	buoy.max_submergence = 2
	buoy.water_drag = -1
	_check(buoy.compute_point_force(Vector3.ZERO, 1, Vector3.ZERO) == Vector3.ZERO,
			"negative drag rejected")
	buoy.water_drag = 2
	_check(buoy.compute_point_force(Vector3(INF, 0, 0), 1, Vector3.ZERO) == Vector3.ZERO,
			"nonfinite float position rejected")
	_check(buoy.compute_point_force(Vector3.ZERO, NAN, Vector3.ZERO) == Vector3.ZERO,
			"nonfinite water height rejected")
	_check(buoy.compute_point_force(Vector3.ZERO, 1, Vector3(NAN, 0, 0)) == Vector3.ZERO,
			"nonfinite velocity rejected")
	buoy.queue_free()


func _test_body_component_integration() -> void:
	var water: WaterSurface3D = Surface.new()
	water.name = "Water"
	root.add_child(water)
	var body := RigidBody3D.new()
	body.position = Vector3(0, -1, 0)
	root.add_child(body)
	var buoy: WaterBuoyancy3D = Buoyancy.new()
	body.add_child(buoy)
	buoy.water_surface_path = NodePath("../../Water")
	buoy.sample_points = PackedVector3Array([Vector3.ZERO])
	_check(buoy.get_parent() == body, "buoyancy component parented to rigidbody")
	_check(buoy.get_node_or_null(buoy.water_surface_path) == water,
			"buoyancy resolves sibling WaterSurface3D")
	buoy._physics_process(0.016)
	_check(true, "water buoyancy physics callback returns without errors")
	buoy.enabled = false
	buoy._physics_process(0.016)
	_check(true, "disabled buoyancy physics callback returns without errors")
	body.queue_free()
	water.queue_free()


func _run_all() -> void:
	_test_calculated_heights()
	_test_analytic_normals()
	_test_time_dependence()
	_test_multiple_waves_and_cancellation()
	_test_empty_and_default_profiles()
	_test_direction_normalization()
	_test_validation()
	_test_invalid_sampling_coordinates()
	_test_uniform_packing()
	_test_water_surface_generation()
	_test_surface_sampling_and_time()
	_test_shader_parameters()
	_test_wave_resource_save_load()
	_test_buoyancy_lift()
	_test_invalid_buoyancy()
	_test_body_component_integration()
	print("Water System: %d assertions; %d failures" % [assertions, failures])
	quit(1 if failures else 0)
