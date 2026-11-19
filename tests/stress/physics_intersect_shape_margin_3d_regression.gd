# Regression: a query margin must expand both the 3D broadphase AABB
# and the narrowphase contact geometry.
# Run with --headless --path tests/stress \
#   --script res://physics_intersect_shape_margin_3d_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var space := PhysicsServer3D.space_create()
	var sphere := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(sphere, 1.0)

	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(body, sphere)
	# The unexpanded sphere AABBs do not intersect: the spheres have
	# a 0.1 gap, which should be bridged by a 0.25 query margin.
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(), Vector3(2.1, 0.0, 0.0)))
	PhysicsServer3D.body_set_space(body, space)
	PhysicsServer3D.space_set_active(space, true)
	await physics_frame
	await process_frame

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape_rid = sphere
	query.transform = Transform3D.IDENTITY
	query.collision_mask = 1
	query.margin = 0.0
	var state := PhysicsServer3D.space_get_direct_state(space)

	var without_margin := state.intersect_shape(query, 1)
	query.margin = 0.25
	var started := Time.get_ticks_usec()
	var within_margin := state.intersect_shape(query, 1)
	var query_us := Time.get_ticks_usec() - started

	# Also check that the result still obeys normal broadphase filters.
	query.collision_mask = 2
	var wrong_layer := state.intersect_shape(query, 1)
	query.collision_mask = 1
	var excluded: Array[RID] = [body]
	query.exclude = excluded
	var excluded_result := state.intersect_shape(query, 1)
	query.exclude = []

	# A collider beyond the query margin must not become a false positive.
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(), Vector3(2.5, 0.0, 0.0)))
	await physics_frame
	await process_frame
	var outside_margin := state.intersect_shape(query, 1)

	var passed := without_margin.is_empty() and within_margin.size() == 1
	if within_margin.size() == 1:
		passed = passed and within_margin[0].rid == body
	passed = passed and wrong_layer.is_empty() and excluded_result.is_empty()
	passed = passed and outside_margin.is_empty()

	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(sphere)
	PhysicsServer3D.free_rid(space)

	if not passed:
		printerr("3D intersect_shape margin regression FAILED: zero=", without_margin.size(),
				" margin=", within_margin.size(), " filtered=", wrong_layer.size(),
				" excluded=", excluded_result.size(), " far=", outside_margin.size())
		quit(1)
		return
	print("3D intersect_shape margin regression passed: positive margin reached near collider; query_us=", query_us)
	quit(0)
