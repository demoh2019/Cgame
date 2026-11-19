extends SceneTree

# Real Jolt PhysicsServer3D regression for opt-in material combination.
# Normally invoked by test_jolt_material_mix.py with a temporary project
# selecting "Jolt Physics" and a single material mode per process.

const PREFIX := "JOLT_MATERIAL_MIX_RESULT:"
const FRICTION_FRAMES := 90
const BOUNCE_FRAMES := 115


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var engine_name := str(ProjectSettings.get_setting("physics/3d/physics_engine", ""))
	if engine_name != "Jolt Physics":
		printerr("Expected the Jolt Physics backend, got: " + engine_name)
		quit(1)
		return

	var scenario := str(ProjectSettings.get_setting("cgame_test/scenario", "friction"))
	if scenario != "friction" and scenario != "bounce":
		printerr("Unknown Jolt material scenario: " + scenario)
		quit(1)
		return

	var space := PhysicsServer3D.space_create()
	var floor_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(floor_shape, Vector3(300.0, 1.0, 300.0))
	var sphere_shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(sphere_shape, 0.5)

	var floor := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(floor, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(floor, floor_shape)
	PhysicsServer3D.body_set_param(floor, PhysicsServer3D.BODY_PARAM_FRICTION, 1.0)
	PhysicsServer3D.body_set_param(floor, PhysicsServer3D.BODY_PARAM_BOUNCE, 0.1)
	PhysicsServer3D.body_set_space(floor, space)

	var ball := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(ball, PhysicsServer3D.BODY_MODE_RIGID_LINEAR if scenario == "friction" else PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_add_shape(ball, sphere_shape)
	PhysicsServer3D.body_set_param(ball, PhysicsServer3D.BODY_PARAM_FRICTION, 0.25)
	PhysicsServer3D.body_set_param(ball, PhysicsServer3D.BODY_PARAM_BOUNCE, 0.3 if scenario == "bounce" else 0.0)
	PhysicsServer3D.body_set_param(ball, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
	PhysicsServer3D.body_set_param(ball, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 0.0)
	PhysicsServer3D.body_set_state(ball, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	if scenario == "friction":
		PhysicsServer3D.body_set_state(ball, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0.0, 1.05, 0.0)))
		PhysicsServer3D.body_set_state(ball, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3(8.0, 0.0, 0.0))
	else:
		PhysicsServer3D.body_set_state(ball, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0.0, 4.0, 0.0)))
		PhysicsServer3D.body_set_state(ball, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3(0.0, -6.0, 0.0))
	PhysicsServer3D.body_set_space(ball, space)
	PhysicsServer3D.space_set_active(space, true)

	var peak_upward_speed := 0.0
	for frame in range(FRICTION_FRAMES if scenario == "friction" else BOUNCE_FRAMES):
		await physics_frame
		if scenario == "bounce":
			var velocity: Vector3 = PhysicsServer3D.body_get_state(ball, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			peak_upward_speed = maxf(peak_upward_speed, velocity.y)

	var final_velocity: Vector3 = PhysicsServer3D.body_get_state(ball, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var passed := final_velocity.is_finite() and is_finite(peak_upward_speed)
	var reading: float = absf(final_velocity.x) if scenario == "friction" else peak_upward_speed
	passed = passed and is_finite(reading)

	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(ball)
	PhysicsServer3D.free_rid(floor)
	PhysicsServer3D.free_rid(sphere_shape)
	PhysicsServer3D.free_rid(floor_shape)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"passed": passed,
		"scenario": scenario,
		"reading": reading,
		"final_velocity": [final_velocity.x, final_velocity.y, final_velocity.z],
	}))
	quit(0 if passed else 1)
