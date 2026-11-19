extends RefCounted
## Real contact-load regression for 3D torsional (spinning) and rolling friction.
## Newly touching bodies must slow on the FIRST loaded step, with no air drag.


func _probe(tree: SceneTree, scale: int, frames: int, spin_coeff: float, roll_coeff: float, axis: Vector3, airborne: bool) -> Dictionary:
	ProjectSettings.set_setting("physics/3d/solver/spinning_friction", spin_coeff)
	ProjectSettings.set_setting("physics/3d/solver/rolling_friction", roll_coeff)
	# GodotSpace3D reads both coefficients at space creation.
	var space := PhysicsServer3D.space_create()
	var sphere := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(sphere, 0.5)
	var ground_shape := PhysicsServer3D.box_shape_create()
	var count := 4 * mini(scale, 8)
	PhysicsServer3D.shape_set_data(ground_shape, Vector3(float(count) * 2.0, 0.25, 3.0))
	var ground := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(ground, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(ground, ground_shape)
	PhysicsServer3D.body_set_param(ground, PhysicsServer3D.BODY_PARAM_FRICTION, 0.0)
	PhysicsServer3D.body_set_state(ground, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(), Vector3(0.0, -0.25, 0.0)))
	PhysicsServer3D.body_set_space(ground, space)
	var bodies: Array[RID] = []
	bodies.resize(count)
	for i in range(count):
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(body, sphere)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_FRICTION, 0.0)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 0.0)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 0.0)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0 if airborne else 1.0)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3((float(i) - float(count - 1) * 0.5) * 2.0, 4.0 if airborne else 0.49, 0.0)))
		PhysicsServer3D.body_set_space(body, space)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, axis * 20.0)
		bodies[i] = body
	PhysicsServer3D.space_set_active(space, true)
	var started := Time.get_ticks_usec()
	var early_speed := 0.0
	var final_speed := 0.0
	var finite := true
	var paired := false
	var steps := mini(maxi(frames, 6), 30)
	for frame in range(steps):
		await tree.physics_frame
		if PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_COLLISION_PAIRS) > 0:
			paired = true
		var speed_sum := 0.0
		for body in bodies:
			var omega: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
			finite = finite and omega.is_finite()
			speed_sum += absf(omega.dot(axis))
		if frame == 2:
			early_speed = speed_sum / float(count)
		if frame == steps - 1:
			final_speed = speed_sum / float(count)
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(ground)
	PhysicsServer3D.free_rid(sphere)
	PhysicsServer3D.free_rid(ground_shape)
	PhysicsServer3D.free_rid(space)
	return {"bodies": count, "early_speed": early_speed, "final_speed": final_speed,
		"finite": finite, "paired": paired, "simulation_ms": elapsed_ms}


func run(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var key_spin := "physics/3d/solver/spinning_friction"
	var key_roll := "physics/3d/solver/rolling_friction"
	var prior_spin = ProjectSettings.get_setting(key_spin)
	var prior_roll = ProjectSettings.get_setting(key_roll)
	var baseline_spin: Dictionary = await _probe(tree, scale, frames, 0.0, 0.0, Vector3.UP, false)
	var loaded_spin: Dictionary = await _probe(tree, scale, frames, 8.0, 0.0, Vector3.UP, false)
	var baseline_roll: Dictionary = await _probe(tree, scale, frames, 0.0, 0.0, Vector3.RIGHT, false)
	var loaded_roll: Dictionary = await _probe(tree, scale, frames, 0.0, 8.0, Vector3.RIGHT, false)
	var in_air: Dictionary = await _probe(tree, scale, frames, 8.0, 8.0, Vector3.UP, true)
	ProjectSettings.set_setting(key_spin, prior_spin)
	ProjectSettings.set_setting(key_roll, prior_roll)

	# No material tangent friction or body damping: only the new angular
	# contact rows can slow a sphere spinning around the contact normal.
	var pass := (
		baseline_spin.finite and loaded_spin.finite and
		baseline_roll.finite and loaded_roll.finite and in_air.finite and
		baseline_spin.paired and loaded_spin.paired and
		baseline_roll.paired and loaded_roll.paired and not in_air.paired and
		loaded_spin.early_speed + 0.05 < baseline_spin.early_speed and
		loaded_spin.final_speed + 0.1 < baseline_spin.final_speed and
		loaded_roll.early_speed + 0.05 < baseline_roll.early_speed and
		loaded_roll.final_speed + 0.1 < baseline_roll.final_speed and
		in_air.final_speed > 18.0
	)
	if not pass:
		return {"error": "Iterative 3D angular contact friction lost load-dependent resistance",
			"baseline_spin": baseline_spin, "loaded_spin": loaded_spin,
			"baseline_roll": baseline_roll, "loaded_roll": loaded_roll,
			"free_flight": in_air}
	return {"spinning_friction_verified": true, "rolling_friction_verified": true,
		"free_flight_undamped": true,
		"baseline_spin": baseline_spin, "loaded_spin": loaded_spin,
		"baseline_roll": baseline_roll, "loaded_roll": loaded_roll,
		"free_flight": in_air}
