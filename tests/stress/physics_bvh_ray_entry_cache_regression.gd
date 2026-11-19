# Regression: nearest clipped ray must not skip a more recent BVH candidate
# after the ray is shortened. Also tests the second broadphase tree and masks.
# Run with: --headless --path tests/stress \
#   --script res://physics_bvh_ray_entry_cache_regression.gd
extends SceneTree

const BODY_COUNT := 4096
const STEP := 3.0
const END_X := float(BODY_COUNT) * STEP + 5.0
const LAST_X := float(BODY_COUNT - 1) * STEP
const REPEATS := 24


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var two: Dictionary = await _test_2d()
	var three: Dictionary = await _test_3d()
	if two.has("error") or three.has("error"):
		printerr("Cached BVH ray entry regression FAILED: 2D=", two, " 3D=", three)
		quit(1)
		return
	print("Cached BVH ray entry regression OK: 2D=", two, " 3D=", three)
	quit(0)


func _test_2d() -> Dictionary:
	var space := PhysicsServer2D.space_create()
	var shape := PhysicsServer2D.rectangle_shape_create()
	PhysicsServer2D.shape_set_data(shape, Vector2(0.5, 0.5))
	var bodies: Array[RID] = []
	for i in range(BODY_COUNT):
		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(body, shape)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(0.0, Vector2(float(i) * STEP, 0.0)))
		PhysicsServer2D.body_set_space(body, space)
		bodies.append(body)
	PhysicsServer2D.space_set_active(space, true)
	await physics_frame
	await process_frame

	var query := PhysicsRayQueryParameters2D.new()
	query.from = Vector2(-5, 0)
	query.to = Vector2(END_X, 0)
	query.collision_mask = 1
	var state := PhysicsServer2D.space_get_direct_state(space)
	var failures := 0
	var start := Time.get_ticks_usec()
	for _repetition in range(REPEATS):
		var result := state.intersect_ray(query)
		if result.is_empty() or result.rid != bodies[0]:
			failures += 1
	var query_us := Time.get_ticks_usec() - start

	var excluded: Array[RID] = [bodies[0]]
	query.exclude = excluded
	var after_exclusion := state.intersect_ray(query)
	var exclusion_ok := not after_exclusion.is_empty() and after_exclusion.rid == bodies[1]
	query.exclude = []

	query.from = Vector2(END_X, 0)
	query.to = Vector2(-5, 0)
	var reverse := state.intersect_ray(query)
	var reverse_ok := not reverse.is_empty() and reverse.rid == bodies[BODY_COUNT - 1]

	query.collision_mask = 2
	var masked := state.intersect_ray(query)
	var mask_ok := masked.is_empty()

	PhysicsServer2D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(shape)
	PhysicsServer2D.free_rid(space)

	if failures > 0 or not exclusion_ok or not reverse_ok or not mask_ok:
		return {"error": "2D ray clipped past a nearer eligible collider",
				"failed_queries": failures, "exclusion": exclusion_ok, "reverse": reverse_ok, "mask": mask_ok}
	return {"bodies": BODY_COUNT, "rays": REPEATS + 3, "query_us": query_us}


func _test_3d() -> Dictionary:
	var space := PhysicsServer3D.space_create()
	var shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(shape, Vector3(0.5, 0.5, 0.5))
	var bodies: Array[RID] = []
	for i in range(BODY_COUNT):
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3(float(i) * STEP, 0.0, 0.0)))
		PhysicsServer3D.body_set_space(body, space)
		bodies.append(body)
	PhysicsServer3D.space_set_active(space, true)
	await physics_frame
	await process_frame

	var query := PhysicsRayQueryParameters3D.new()
	query.from = Vector3(-5, 0, 0)
	query.to = Vector3(END_X, 0, 0)
	query.collision_mask = 1
	var state := PhysicsServer3D.space_get_direct_state(space)
	var failures := 0
	var start := Time.get_ticks_usec()
	for _repetition in range(REPEATS):
		var result := state.intersect_ray(query)
		if result.is_empty() or result.rid != bodies[0]:
			failures += 1
	var query_us := Time.get_ticks_usec() - start

	var excluded: Array[RID] = [bodies[0]]
	query.exclude = excluded
	var after_exclusion := state.intersect_ray(query)
	var exclusion_ok := not after_exclusion.is_empty() and after_exclusion.rid == bodies[1]
	query.exclude = []

	query.from = Vector3(END_X, 0, 0)
	query.to = Vector3(-5, 0, 0)
	var reverse := state.intersect_ray(query)
	var reverse_ok := not reverse.is_empty() and reverse.rid == bodies[BODY_COUNT - 1]

	query.collision_mask = 2
	var masked := state.intersect_ray(query)
	var mask_ok := masked.is_empty()

	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(space)

	if failures > 0 or not exclusion_ok or not reverse_ok or not mask_ok:
		return {"error": "3D ray clipped past a nearer eligible collider",
				"failed_queries": failures, "exclusion": exclusion_ok, "reverse": reverse_ok, "mask": mask_ok}
	return {"bodies": BODY_COUNT, "rays": REPEATS + 3, "query_us": query_us}
