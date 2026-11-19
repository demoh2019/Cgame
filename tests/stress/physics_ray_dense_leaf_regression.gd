# Dense-leaf raycast correctness and performance regression for 2D and 3D.
# Run: godot --headless --path tests/stress --script res://physics_ray_dense_leaf_regression.gd
extends SceneTree

const TRACKS := 32
const PER_TRACK := 64
const QUERY_REPEATS := 20
const SPACING := 4.0
const TRACK_SPACING := 8.0
const RADIUS := 0.5


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var result_2d := await _test_2d()
	var result_3d := await _test_3d()
	if result_2d.has("error") or result_3d.has("error"):
		printerr("Dense BVH leaf raycast regression failed: 2D=", result_2d, " 3D=", result_3d)
		quit(1)
		return
	print("Dense BVH leaf raycast regression passed: 2D=", result_2d, " 3D=", result_3d)
	quit(0)


func _test_2d() -> Dictionary:
	var shape := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(shape, RADIUS)
	var space := root.get_world_2d().space
	var bodies: Array[RID] = []
	var creation_start := Time.get_ticks_usec()
	for track in range(TRACKS):
		for i in range(PER_TRACK):
			# Deliberately insert far-to-near within each row, so the nearest
			# proxy is encountered late by an unordered BVH leaf iteration.
			var x := float(PER_TRACK - 1 - i) * SPACING
			var y := float(track) * TRACK_SPACING
			var body := PhysicsServer2D.body_create()
			PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
			PhysicsServer2D.body_add_shape(body, shape)
			PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2(x, y)))
			PhysicsServer2D.body_set_space(body, space)
			bodies.append(body)
	var creation_ms := float(Time.get_ticks_usec() - creation_start) / 1000.0

	await physics_frame
	await process_frame
	var state := root.get_world_2d().direct_space_state
	var total_hits := 0
	var failure := ""
	var query_start := Time.get_ticks_usec()
	for track in range(TRACKS):
		var y := float(track) * TRACK_SPACING
		var query := PhysicsRayQueryParameters2D.create(Vector2(-2.0, y), Vector2(float(PER_TRACK) * SPACING + 2.0, y))
		for _repeat in range(QUERY_REPEATS):
			var result := state.intersect_ray(query)
			if result.is_empty() or absf(result.position.x + RADIUS) > 0.05:
				failure = "2D nearest hit incorrect on row %d" % track
				break
			total_hits += 1
		if failure != "":
			break
		var reverse := PhysicsRayQueryParameters2D.create(query.to, query.from)
		var last := state.intersect_ray(reverse)
		if last.is_empty() or absf(last.position.x - (float(PER_TRACK - 1) * SPACING + RADIUS)) > 0.05:
			failure = "2D reverse nearest hit incorrect on row %d" % track
			break
	var query_ms := float(Time.get_ticks_usec() - query_start) / 1000.0

	for body in bodies:
		PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(shape)
	if failure != "":
		return {"error": failure, "bodies": bodies.size(), "queries_completed": total_hits}
	return {"bodies": TRACKS * PER_TRACK, "queries": total_hits + TRACKS, "creation_ms": creation_ms, "query_ms": query_ms}


func _test_3d() -> Dictionary:
	var shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, RADIUS)
	var space := root.get_world_3d().space
	var bodies: Array[RID] = []
	var creation_start := Time.get_ticks_usec()
	for track in range(TRACKS):
		for i in range(PER_TRACK):
			var x := float(PER_TRACK - 1 - i) * SPACING
			var y := float(track) * TRACK_SPACING
			var body := PhysicsServer3D.body_create()
			PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
			PhysicsServer3D.body_add_shape(body, shape)
			PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(x, y, 0.0)))
			PhysicsServer3D.body_set_space(body, space)
			bodies.append(body)
	var creation_ms := float(Time.get_ticks_usec() - creation_start) / 1000.0

	await physics_frame
	await process_frame
	var state := root.get_world_3d().direct_space_state
	var total_hits := 0
	var failure := ""
	var query_start := Time.get_ticks_usec()
	for track in range(TRACKS):
		var y := float(track) * TRACK_SPACING
		var query := PhysicsRayQueryParameters3D.create(Vector3(-2.0, y, 0.0), Vector3(float(PER_TRACK) * SPACING + 2.0, y, 0.0))
		for _repeat in range(QUERY_REPEATS):
			var result := state.intersect_ray(query)
			if result.is_empty() or absf(result.position.x + RADIUS) > 0.05:
				failure = "3D nearest hit incorrect on row %d" % track
				break
			total_hits += 1
		if failure != "":
			break
		var reverse := PhysicsRayQueryParameters3D.create(query.to, query.from)
		var last := state.intersect_ray(reverse)
		if last.is_empty() or absf(last.position.x - (float(PER_TRACK - 1) * SPACING + RADIUS)) > 0.05:
			failure = "3D reverse nearest hit incorrect on row %d" % track
			break
	var query_ms := float(Time.get_ticks_usec() - query_start) / 1000.0

	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(shape)
	if failure != "":
		return {"error": failure, "bodies": bodies.size(), "queries_completed": total_hits}
	return {"bodies": TRACKS * PER_TRACK, "queries": total_hits + TRACKS, "creation_ms": creation_ms, "query_ms": query_ms}
