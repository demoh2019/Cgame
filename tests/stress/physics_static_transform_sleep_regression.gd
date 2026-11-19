# Headless regression: identical static-body transform must not wake linked rigid bodies.
# Run: godot --headless --path tests/stress --script res://physics_static_transform_sleep_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var errors := 0

	var space_2d := PhysicsServer2D.space_create()
	var circle := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(circle, 0.4)
	var static_2d := PhysicsServer2D.body_create()
	var rigid_2d := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(static_2d, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_set_mode(rigid_2d, PhysicsServer2D.BODY_MODE_RIGID)
	PhysicsServer2D.body_add_shape(static_2d, circle)
	PhysicsServer2D.body_add_shape(rigid_2d, circle)
	PhysicsServer2D.body_set_param(rigid_2d, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	PhysicsServer2D.body_set_space(static_2d, space_2d)
	PhysicsServer2D.body_set_space(rigid_2d, space_2d)
	var joint_2d := PhysicsServer2D.joint_create()
	PhysicsServer2D.joint_make_pin(joint_2d, Vector2.ZERO, static_2d, rigid_2d)
	PhysicsServer2D.space_set_active(space_2d, true)

	var space_3d := PhysicsServer3D.space_create()
	var sphere := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(sphere, 0.4)
	var static_3d := PhysicsServer3D.body_create()
	var rigid_3d := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(static_3d, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_mode(rigid_3d, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_add_shape(static_3d, sphere)
	PhysicsServer3D.body_add_shape(rigid_3d, sphere)
	PhysicsServer3D.body_set_param(rigid_3d, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	PhysicsServer3D.body_set_space(static_3d, space_3d)
	PhysicsServer3D.body_set_space(rigid_3d, space_3d)
	var joint_3d := PhysicsServer3D.joint_create()
	PhysicsServer3D.joint_make_pin(joint_3d, static_3d, Vector3.ZERO, rigid_3d, Vector3.ZERO)
	PhysicsServer3D.space_set_active(space_3d, true)

	await physics_frame
	await physics_frame

	# Explicitly put both connected rigid bodies to sleep. Repeating an
	# unchanged static transform must never reactivate them.
	PhysicsServer2D.body_set_state(rigid_2d, PhysicsServer2D.BODY_STATE_SLEEPING, true)
	PhysicsServer3D.body_set_state(rigid_3d, PhysicsServer3D.BODY_STATE_SLEEPING, true)
	if not bool(PhysicsServer2D.body_get_state(rigid_2d, PhysicsServer2D.BODY_STATE_SLEEPING)) or \
			not bool(PhysicsServer3D.body_get_state(rigid_3d, PhysicsServer3D.BODY_STATE_SLEEPING)):
		printerr("FAIL: rigid bodies could not be put to sleep")
		errors += 1

	var static_pose_2d := Transform2D.IDENTITY
	var static_pose_3d := Transform3D.IDENTITY
	for i in range(128):
		PhysicsServer2D.body_set_state(static_2d, PhysicsServer2D.BODY_STATE_TRANSFORM, static_pose_2d)
		PhysicsServer3D.body_set_state(static_3d, PhysicsServer3D.BODY_STATE_TRANSFORM, static_pose_3d)
		if not bool(PhysicsServer2D.body_get_state(rigid_2d, PhysicsServer2D.BODY_STATE_SLEEPING)):
			printerr("FAIL: identical 2D static transform woke a rigid neighbor at iteration %d" % i)
			errors += 1
			break
		if not bool(PhysicsServer3D.body_get_state(rigid_3d, PhysicsServer3D.BODY_STATE_SLEEPING)):
			printerr("FAIL: identical 3D static transform woke a rigid neighbor at iteration %d" % i)
			errors += 1
			break

	# A *different* static transform still invalidates bounds and wakes
	# linked dynamics. This checks that the fast path is truly conditional.
	PhysicsServer2D.body_set_state(static_2d, PhysicsServer2D.BODY_STATE_TRANSFORM,
			Transform2D(0.0, Vector2(0.25, 0.0)))
	PhysicsServer3D.body_set_state(static_3d, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(), Vector3(0.25, 0.0, 0.0)))
	if bool(PhysicsServer2D.body_get_state(rigid_2d, PhysicsServer2D.BODY_STATE_SLEEPING)):
		printerr("FAIL: changed 2D static transform did not wake its rigid neighbor")
		errors += 1
	if bool(PhysicsServer3D.body_get_state(rigid_3d, PhysicsServer3D.BODY_STATE_SLEEPING)):
		printerr("FAIL: changed 3D static transform did not wake its rigid neighbor")
		errors += 1

	PhysicsServer2D.space_set_active(space_2d, false)
	PhysicsServer3D.space_set_active(space_3d, false)
	PhysicsServer2D.free_rid(joint_2d)
	PhysicsServer3D.free_rid(joint_3d)
	PhysicsServer2D.free_rid(static_2d)
	PhysicsServer2D.free_rid(rigid_2d)
	PhysicsServer3D.free_rid(static_3d)
	PhysicsServer3D.free_rid(rigid_3d)
	PhysicsServer2D.free_rid(circle)
	PhysicsServer3D.free_rid(sphere)
	PhysicsServer2D.free_rid(space_2d)
	PhysicsServer3D.free_rid(space_3d)
	if errors == 0:
		print("2D/3D unchanged static transform and neighbor sleep regression passed.")
	else:
		printerr("Static transform sleep regression failed: %d error(s)" % errors)
	quit(1 if errors > 0 else 0)
