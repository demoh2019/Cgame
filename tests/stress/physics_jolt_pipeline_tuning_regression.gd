extends SceneTree

# Dense native-Jolt smoke/regression for the pipeline tuning settings.
# test_jolt_pipeline_tuning.py runs this script in separately configured
# projects to verify both low-memory and high-parallelism configurations.

const PREFIX := "JOLT_PIPELINE_RESULT:"
const BODY_COUNT := 144
const SIDE := 12
const FRAMES := 20

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if str(ProjectSettings.get_setting("physics/3d/physics_engine", "")) != "Jolt Physics":
		printerr("This test requires Jolt Physics.")
		quit(1)
		return

	var space: RID = PhysicsServer3D.space_create()
	var shape: RID = PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, 0.5)
	var bodies: Array[RID] = []

	for i in range(BODY_COUNT):
		var body: RID = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP_MODE,
				PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 0.0)
		var x: float = float(i % SIDE) * 0.9
		var y: float = float(int(i / SIDE)) * 0.9
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3(x, y, 0.0)))
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY,
				Vector3(0.03 if i % 2 == 0 else -0.03, 0.0, 0.0))
		PhysicsServer3D.body_set_space(body, space)
		bodies.append(body)

	PhysicsServer3D.space_set_active(space, true)
	var peak_active := 0
	var peak_pairs := 0
	for frame in range(FRAMES):
		await physics_frame
		peak_active = maxi(peak_active, PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_ACTIVE_OBJECTS))
		peak_pairs = maxi(peak_pairs, PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_COLLISION_PAIRS))

	var all_finite := true
	for body in bodies:
		var transform: Transform3D = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM)
		var velocity: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		all_finite = all_finite and transform.origin.is_finite() and velocity.is_finite()
		PhysicsServer3D.free_rid(body)

	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(space)

	var passed := all_finite and peak_active > 0 and peak_active <= BODY_COUNT and peak_pairs > 0
	print(PREFIX + JSON.stringify({
		"passed": passed,
		"bodies": BODY_COUNT,
		"frames": FRAMES,
		"peak_active": peak_active,
		"peak_pairs": peak_pairs,
		"finite": all_finite,
		"max_in_flight_body_pairs": ProjectSettings.get_setting(
				"physics/jolt_physics_3d/limits/max_in_flight_body_pairs"),
		"large_island_splitter": ProjectSettings.get_setting(
				"physics/jolt_physics_3d/simulation/use_large_island_splitter"),
		"manifold_reduction": ProjectSettings.get_setting(
				"physics/jolt_physics_3d/simulation/use_manifold_reduction"),
		"max_penetration_correction_distance": ProjectSettings.get_setting(
				"physics/jolt_physics_3d/simulation/max_penetration_correction_distance"),
		"contact_manifold_merge_angle": ProjectSettings.get_setting(
				"physics/jolt_physics_3d/simulation/contact_manifold_merge_angle"),
		"contact_warm_start_distance": ProjectSettings.get_setting(
				"physics/jolt_physics_3d/simulation/contact_warm_start_distance"),
	}))
	quit(0 if passed else 1)
