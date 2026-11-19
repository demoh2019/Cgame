# Box2D-style analytic manifold for exactly coincident 2D circle centers.
# Run: godot --headless --path tests/stress --script res://physics_coincident_circles_2d_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var space := PhysicsServer2D.space_create()
	var static_circle := PhysicsServer2D.circle_shape_create()
	var moving_circle := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(static_circle, 0.7)
	PhysicsServer2D.shape_set_data(moving_circle, 0.6)

	var static_body := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(static_body, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(static_body, static_circle)
	PhysicsServer2D.body_set_space(static_body, space)
	PhysicsServer2D.space_set_active(space, true)

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape_rid = moving_circle
	query.margin = 0.0
	var failures := 0
	for mode in range(3):
		var center := Vector2(float(mode) * 10.0, 0.0)
		PhysicsServer2D.body_set_state(static_body, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(0.0, center))
		await physics_frame
		var state: PhysicsDirectSpaceState2D = PhysicsServer2D.space_get_direct_state(space)
		if state == null:
			printerr("FAIL: direct 2D state unavailable")
			failures += 1
			break
		# Nonuniform scale must use generic SAT; both other modes use the
		# analytic path, with exactly equal or slightly separated centers.
		var cases := [
			{"offset": Vector2.ZERO, "hit": true},
			{"offset": Vector2(0.02, 0.0), "hit": true},
			{"offset": Vector2(-0.1, 0.0), "hit": true},
			{"offset": Vector2(1.15, 0.0), "hit": true},
			{"offset": Vector2(1.7, 0.0), "hit": false},
		]
		if mode == 2:
			cases = [
				{"offset": Vector2.ZERO, "hit": true},
				{"offset": Vector2(2.1, 0.0), "hit": false},
			]
		for test_case in cases:
			var offset: Vector2 = test_case["offset"]
			var transform := Transform2D(0.37 if mode == 1 else 0.0, center + offset)
			if mode == 2:
				transform = transform.scaled_local(Vector2(1.5, 1.0))
			query.transform = transform
			var hit := not state.intersect_shape(query, 8).is_empty()
			if hit != bool(test_case["hit"]):
				printerr("FAIL: coincident circles mode=%d offset=%s expected=%s hit=%s" %
						[mode, offset, test_case["hit"], hit])
				failures += 1
			if hit and bool(test_case["hit"]):
				var points: PackedVector2Array = state.collide_shape(query, 8)
				if points.is_empty():
					printerr("FAIL: no circle contact for mode=%d offset=%s" % [mode, offset])
					failures += 1
				for point in points:
					if not point.is_finite():
						printerr("FAIL: nonfinite 2D coincident circle contact")
						failures += 1
						break

	# Exercise the rigid-body solver as well as geometric queries: a circle
	# initialized at the same center as a static one must not produce NaNs
	# or remain hopelessly coincident after penetration correction.
	PhysicsServer2D.body_set_state(static_body, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D.IDENTITY)
	var rigid_body := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(rigid_body, PhysicsServer2D.BODY_MODE_RIGID)
	PhysicsServer2D.body_add_shape(rigid_body, moving_circle)
	PhysicsServer2D.body_set_param(rigid_body, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	PhysicsServer2D.body_set_state(rigid_body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
	PhysicsServer2D.body_set_state(rigid_body, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D.IDENTITY)
	PhysicsServer2D.body_set_space(rigid_body, space)
	for frame in range(36):
		await physics_frame
	var pose: Transform2D = PhysicsServer2D.body_get_state(rigid_body, PhysicsServer2D.BODY_STATE_TRANSFORM)
	var velocity: Vector2 = PhysicsServer2D.body_get_state(rigid_body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	if not pose.origin.is_finite() or not velocity.is_finite() or pose.origin.length_squared() < 0.0001:
		printerr("FAIL: coincident rigid circles did not separate stably: %s, velocity=%s" %
				[pose.origin, velocity])
		failures += 1

	PhysicsServer2D.space_set_active(space, false)
	PhysicsServer2D.free_rid(rigid_body)
	PhysicsServer2D.free_rid(static_body)
	PhysicsServer2D.free_rid(moving_circle)
	PhysicsServer2D.free_rid(static_circle)
	PhysicsServer2D.free_rid(space)
	if failures == 0:
		print("Coincident 2D circle analytic manifolds and solver passed.")
	else:
		printerr("Coincident 2D circle regression failed: %d error(s)" % failures)
	quit(1 if failures > 0 else 0)
