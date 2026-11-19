# Regression for an exact 2D BVH point query without a synthetic epsilon AABB.
# Run with: --headless --path tests/stress \
# --script res://physics_2d_exact_point_bvh_regression.gd
extends SceneTree

const DECOYS := 4096
const QUERIES := 64
const DECOY_X := 0.500005


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var space := root.get_world_2d().space
	var shape := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(shape, 0.5)
	var decoys: Array[RID] = []
	for i in range(DECOYS):
		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(body, shape)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(0.0, Vector2(DECOY_X, 0.0)))
		PhysicsServer2D.body_set_space(body, space)
		decoys.append(body)

	# Insert the one exact hit *after* every nearby but non-containing proxy.
	var target := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(target, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(target, shape)
	PhysicsServer2D.body_set_space(target, space)
	PhysicsServer2D.body_set_state(target, PhysicsServer2D.BODY_STATE_TRANSFORM,
			Transform2D(0.0, Vector2.ZERO))

	await physics_frame
	await process_frame

	var state := root.get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = Vector2.ZERO
	query.collision_mask = 1
	var missed := 0
	var begin := Time.get_ticks_usec()
	for _iteration in range(QUERIES):
		var hits := state.intersect_point(query, 1)
		if hits.size() != 1 or hits[0].rid != target:
			missed += 1
	var query_us := Time.get_ticks_usec() - begin

	# Near bodies must still be found if the actual point moves inside them.
	query.position = Vector2(DECOY_X, 0)
	var decoy_hits := state.intersect_point(query, 1)
	var decoy_found := decoy_hits.size() == 1 and decoy_hits[0].rid != target
	query.position = Vector2.ZERO

	query.collision_mask = 2
	var layer_ok := state.intersect_point(query, 1).is_empty()
	query.collision_mask = 1
	var exclude: Array[RID] = [target]
	query.exclude = exclude
	var excluded_ok := state.intersect_point(query, 1).is_empty()
	query.exclude = []

	# Local shape offsets and body transforms must still update the BVH.
	PhysicsServer2D.body_set_shape_transform(target, 0,
			Transform2D(0.27, Vector2(2.0, -1.0)))
	PhysicsServer2D.body_set_state(target, PhysicsServer2D.BODY_STATE_TRANSFORM,
			Transform2D(0.52, Vector2(15, -10)))
	await physics_frame
	await process_frame

	var moved_point := Transform2D(0.52, Vector2(15, -10)) * Transform2D(0.27, Vector2(2.0, -1.0)) * Vector2.ZERO
	query.position = moved_point
	var moved_hits := state.intersect_point(query, 1)
	var moved_ok := moved_hits.size() == 1 and moved_hits[0].rid == target
	query.position = Vector2.ZERO
	var old_point_empty := state.intersect_point(query, 1).is_empty()

	for body in decoys:
		PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(target)
	PhysicsServer2D.free_rid(shape)

	if missed != 0 or not decoy_found or not layer_ok or not excluded_ok or not moved_ok or not old_point_empty:
		printerr("Exact 2D point BVH regression FAILED: missed=", missed,
				" decoy=", decoy_found, " layer=", layer_ok,
				" excluded=", excluded_ok, " moved=", moved_ok,
				" old_empty=", old_point_empty)
		quit(1)
		return
	print("Exact 2D point BVH regression passed: decoys=", DECOYS,
			" queries=", QUERIES, " query_us=", query_us)
	quit(0)
