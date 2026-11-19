# Regression for the opt-in Jolt-style uniform fluid approximation in 2D and 3D.
# Run: godot --headless --path tests/stress --script res://physics_uniform_fluid_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var settings := {
		"physics/2d/solver/fluid_linear_drag": 0.4,
		"physics/2d/solver/fluid_angular_drag": 0.3,
		"physics/2d/solver/fluid_buoyancy": 1.0,
		"physics/2d/solver/fluid_flow_velocity": Vector2(3.0, 0.0),
		"physics/3d/solver/fluid_linear_drag": 0.4,
		"physics/3d/solver/fluid_angular_drag": 0.3,
		"physics/3d/solver/fluid_buoyancy": 1.0,
		"physics/3d/solver/fluid_flow_velocity": Vector3(3.0, 0.0, 0.0),
	}
	var original := {}
	for key in settings.keys():
		original[key] = ProjectSettings.get_setting(key)
		ProjectSettings.set_setting(key, settings[key])

	var space_2d := PhysicsServer2D.space_create()
	var circle := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(circle, 0.5)
	var moving_2d := PhysicsServer2D.body_create()
	var neutral_2d := PhysicsServer2D.body_create()
	for body in [moving_2d, neutral_2d]:
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_RIGID)
		PhysicsServer2D.body_add_shape(body, circle)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_LINEAR_DAMP_MODE, PhysicsServer2D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_ANGULAR_DAMP_MODE, PhysicsServer2D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_LINEAR_DAMP, 0.0)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_ANGULAR_DAMP, 0.0)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer2D.body_set_space(body, space_2d)
	PhysicsServer2D.body_set_param(moving_2d, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	PhysicsServer2D.body_set_state(moving_2d, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2.ZERO))
	PhysicsServer2D.body_set_state(moving_2d, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2(12.0, 0.0))
	PhysicsServer2D.body_set_state(moving_2d, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY, 6.0)
	PhysicsServer2D.body_set_state(neutral_2d, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2(0.0, 100.0)))
	PhysicsServer2D.body_set_state(neutral_2d, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2(3.0, 0.0))
	PhysicsServer2D.body_set_param(neutral_2d, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 1.0)
	PhysicsServer2D.space_set_active(space_2d, true)

	var space_3d := PhysicsServer3D.space_create()
	var sphere := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(sphere, 0.5)
	var moving_3d := PhysicsServer3D.body_create()
	var neutral_3d := PhysicsServer3D.body_create()
	for body in [moving_3d, neutral_3d]:
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(body, sphere)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 0.0)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 0.0)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_space(body, space_3d)
	PhysicsServer3D.body_set_param(moving_3d, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	PhysicsServer3D.body_set_state(moving_3d, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3.ZERO))
	PhysicsServer3D.body_set_state(moving_3d, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3(12.0, 0.0, 0.0))
	PhysicsServer3D.body_set_state(moving_3d, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3(0.0, 6.0, 0.0))
	PhysicsServer3D.body_set_state(neutral_3d, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0.0, 100.0, 0.0)))
	PhysicsServer3D.body_set_state(neutral_3d, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3(3.0, 0.0, 0.0))
	PhysicsServer3D.body_set_param(neutral_3d, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 1.0)
	PhysicsServer3D.space_set_active(space_3d, true)

	for frame in range(60):
		await physics_frame
	var failures := 0

	var v2: Vector2 = PhysicsServer2D.body_get_state(moving_2d, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	var w2: float = PhysicsServer2D.body_get_state(moving_2d, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY)
	var n2: Vector2 = PhysicsServer2D.body_get_state(neutral_2d, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	if not v2.is_finite() or not (3.0 < v2.x and v2.x < 12.0) or not (0.0 < w2 and w2 < 6.0):
		printerr("FAIL: 2D drag/flow response: v=%s w=%s" % [v2, w2])
		failures += 1
	if not n2.is_finite() or n2.distance_to(Vector2(3.0, 0.0)) > 0.1:
		printerr("FAIL: neutral 2D buoyancy did not cancel gravity: %s" % n2)
		failures += 1

	var v3: Vector3 = PhysicsServer3D.body_get_state(moving_3d, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var w3: Vector3 = PhysicsServer3D.body_get_state(moving_3d, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	var n3: Vector3 = PhysicsServer3D.body_get_state(neutral_3d, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	if not v3.is_finite() or not (3.0 < v3.x and v3.x < 12.0) or not (0.0 < w3.y and w3.y < 6.0):
		printerr("FAIL: 3D drag/flow response: v=%s w=%s" % [v3, w3])
		failures += 1
	if not n3.is_finite() or n3.distance_to(Vector3(3.0, 0.0, 0.0)) > 0.1:
		printerr("FAIL: neutral 3D buoyancy did not cancel gravity: %s" % n3)
		failures += 1

	PhysicsServer2D.space_set_active(space_2d, false)
	PhysicsServer3D.space_set_active(space_3d, false)
	for body in [moving_2d, neutral_2d]:
		PhysicsServer2D.free_rid(body)
	for body in [moving_3d, neutral_3d]:
		PhysicsServer3D.free_rid(body)
	PhysicsServer2D.free_rid(circle)
	PhysicsServer3D.free_rid(sphere)
	PhysicsServer2D.free_rid(space_2d)
	PhysicsServer3D.free_rid(space_3d)
	for key in original.keys():
		ProjectSettings.set_setting(key, original[key])
	if failures == 0:
		print("Uniform fluid 2D/3D: relative-flow drag, angular drag and neutral buoyancy passed.")
	else:
		printerr("Uniform fluid regressions failed: %d" % failures)
	quit(1 if failures > 0 else 0)
