# Box2D-style implicit damping must remain opt-in and preserve old projects.
# Run: godot --headless --path tests/stress --script res://physics_implicit_damping_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var saved_ticks := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 60
	var failures := 0
	var results: Array[Dictionary] = []
	for dimension in [2, 3]:
		for enabled in [false, true]:
			var result: Dictionary
			if dimension == 2:
				result = await _measure_2d(enabled)
			else:
				result = await _measure_3d(enabled)
			results.append(result)
			if result.has("error"):
				printerr("FAIL: damping dimension=%d implicit=%s: %s" % [dimension, enabled, result["error"]])
				failures += 1
				continue

			var linear_first: float = result["linear_first"]
			var linear_second: float = result["linear_second"]
			var angular_first: float = result["angular_first"]
			var angular_second: float = result["angular_second"]
			var expected := 1.0 / (1.0 + 120.0 / 60.0)
			if enabled:
				# For a high damping coefficient, explicit Euler abruptly
				# clamps to zero, but Box2D's implicit method approaches zero.
				if linear_first <= 0.0 or angular_first <= 0.0:
					printerr("FAIL: implicit damping stopped a moving body")
					failures += 1
				elif (absf(linear_second / linear_first - expected) > 0.05
						or absf(angular_second / angular_first - expected) > 0.05):
					printerr("FAIL: expected implicit linear/angular velocity factor %f, got %s" % [expected, result])
					failures += 1
			else:
				if linear_first > 0.0001 or angular_first > 0.0001:
					printerr("FAIL: legacy damping no longer clamps high damping to zero")
					failures += 1
			print("DAMPING_RESULT:" + JSON.stringify(result))
	Engine.physics_ticks_per_second = saved_ticks
	quit(1 if failures > 0 else 0)


func _measure_2d(enabled: bool) -> Dictionary:
	var setting := "physics/2d/solver/implicit_damping"
	var original: Variant = ProjectSettings.get_setting(setting, false)
	ProjectSettings.set_setting(setting, enabled)
	var space := PhysicsServer2D.space_create()
	# Changes after creation must not change this space's solver.
	ProjectSettings.set_setting(setting, original)

	var shape := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(shape, 0.5)
	var body := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_RIGID)
	PhysicsServer2D.body_add_shape(body, shape)
	PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_LINEAR_DAMP_MODE, PhysicsServer2D.BODY_DAMP_MODE_REPLACE)
	PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_ANGULAR_DAMP_MODE, PhysicsServer2D.BODY_DAMP_MODE_REPLACE)
	PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_LINEAR_DAMP, 120.0)
	PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_ANGULAR_DAMP, 120.0)
	PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
	PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2(6.0, 0.0))
	PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY, 4.0)
	PhysicsServer2D.body_set_space(body, space)
	PhysicsServer2D.space_set_active(space, true)

	await physics_frame
	await physics_frame
	var first: Vector2 = PhysicsServer2D.body_get_state(body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	var first_angular: float = PhysicsServer2D.body_get_state(body, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY)
	await physics_frame
	var second: Vector2 = PhysicsServer2D.body_get_state(body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	var second_angular: float = PhysicsServer2D.body_get_state(body, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY)

	PhysicsServer2D.space_set_active(space, false)
	PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(shape)
	PhysicsServer2D.free_rid(space)
	if not first.is_finite() or not second.is_finite() or is_nan(first_angular) or is_inf(first_angular) or is_nan(second_angular) or is_inf(second_angular):
		return {"error": "non-finite 2D damping state"}
	return {
		"dimension": 2, "implicit_damping": enabled,
		"linear_first": first.length(), "linear_second": second.length(),
		"angular_first": absf(first_angular), "angular_second": absf(second_angular),
	}


func _measure_3d(enabled: bool) -> Dictionary:
	var setting := "physics/3d/solver/implicit_damping"
	var original: Variant = ProjectSettings.get_setting(setting, false)
	ProjectSettings.set_setting(setting, enabled)
	var space := PhysicsServer3D.space_create()
	ProjectSettings.set_setting(setting, original)

	var shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, 0.5)
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 120.0)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 120.0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3(6.0, 0.0, 0.0))
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3(0.0, 0.0, 4.0))
	PhysicsServer3D.body_set_space(body, space)
	PhysicsServer3D.space_set_active(space, true)

	await physics_frame
	await physics_frame
	var first: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var first_angular: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	await physics_frame
	var second: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var second_angular: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)

	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(space)
	if not first.is_finite() or not second.is_finite() or not first_angular.is_finite() or not second_angular.is_finite():
		return {"error": "non-finite 3D damping state"}
	return {
		"dimension": 3, "implicit_damping": enabled,
		"linear_first": first.length(), "linear_second": second.length(),
		"angular_first": first_angular.length(), "angular_second": second_angular.length(),
	}
