# Integration regression for persistent multi-point contact manifolds in 3D.
# Run: godot --headless --path tests/stress --script res://physics_manifold_3d_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var space: RID = PhysicsServer3D.space_create()
	var floor_shape: RID = PhysicsServer3D.box_shape_create()
	var box_shape: RID = PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(floor_shape, Vector3(20.0, 0.5, 20.0))
	PhysicsServer3D.shape_set_data(box_shape, Vector3(0.5, 0.5, 0.5))

	var floor: RID = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(floor, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(floor, floor_shape)
	PhysicsServer3D.body_set_param(floor, PhysicsServer3D.BODY_PARAM_FRICTION, 0.75)
	PhysicsServer3D.body_set_space(floor, space)

	var boxes: Array[RID] = []
	for i in range(8):
		var body: RID = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(body, box_shape)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 1.0)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_FRICTION, 0.75)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		var x: float = float(i % 2) * 4.0 - 2.0
		var height: float = 1.25 + float(int(i / 2)) * 1.05
		var angle: float = float(i % 4) * 0.025
		var transform: Transform3D = Transform3D(Basis(Vector3.FORWARD, angle), Vector3(x, height, 0.0))
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, transform)
		PhysicsServer3D.body_set_space(body, space)
		boxes.append(body)

	PhysicsServer3D.space_set_active(space, true)

	var failures: int = 0
	var peak_pairs: int = 0
	for frame in range(210):
		await physics_frame
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
		for body in boxes:
			var transform: Transform3D = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM)
			var velocity: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			var angular_velocity: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
			if not transform.origin.is_finite() or not velocity.is_finite() or not angular_velocity.is_finite():
				printerr("FAIL: non-finite manifold state on frame %d" % frame)
				failures += 1
				break
			if transform.origin.y < -10.0 or velocity.length_squared() > 1000000.0:
				printerr("FAIL: contact escaped floor or gained excessive energy on frame %d" % frame)
				failures += 1
				break
		if failures != 0:
			break

	if peak_pairs < 4:
		printerr("FAIL: insufficient multi-contact interactions (%d)" % peak_pairs)
		failures += 1

	PhysicsServer3D.space_set_active(space, false)
	for body in boxes:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(floor)
	PhysicsServer3D.free_rid(box_shape)
	PhysicsServer3D.free_rid(floor_shape)
	PhysicsServer3D.free_rid(space)

	if failures == 0:
		print("3D multi-contact manifold regression passed (peak_pairs=%d)." % peak_pairs)
		quit(0)
	else:
		printerr("3D multi-contact manifold regression failed (%d error(s))." % failures)
		quit(1)
