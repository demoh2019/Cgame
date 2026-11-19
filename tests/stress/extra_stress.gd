extends RefCounted
## Additional isolated stress workloads. Called by stress.gd, not directly.
## Each case validates its own output so speedups cannot hide incorrect results.

var _contention_mutex := Mutex.new()
var _contention_counter := 0


func run_case(test_case: String, tree: SceneTree, scale: int, frames: int, seed: int) -> Dictionary:
	match test_case:
		"compression":
			return _compression(scale, seed)
		"regex":
			return _regex(scale)
		"astar_3d":
			return _astar_3d(scale)
		"scene_reparent":
			return _scene_reparent(tree, scale)
		"resource_roundtrip":
			return _resource_roundtrip(scale)
		"thread_contention":
			return _thread_contention(scale)
		"physics_queries_2d":
			return await _physics_queries_2d(tree, scale, frames)
		"render_multimesh":
			return await _render_multimesh(tree, scale, frames)
	return {"error": "Unhandled additional stress case: " + test_case}


func _compression(scale: int, seed: int) -> Dictionary:
	var payload := PackedByteArray()
	payload.resize(131072)
	for i in range(payload.size()):
		payload[i] = ((i * 1103515245 + seed) >> 11) & 255
	var total_input := 0
	var total_encoded := 0
	for i in range(80 * scale):
		payload[0] = i & 255
		payload[1] = (i >> 8) & 255
		var encoded := payload.compress(FileAccess.COMPRESSION_ZSTD)
		if encoded.is_empty():
			return {"error": "Compression produced no data"}
		var decoded := encoded.decompress(payload.size(), FileAccess.COMPRESSION_ZSTD)
		if decoded != payload:
			return {"error": "Compression roundtrip mismatch at iteration %d" % i}
		total_input += payload.size()
		total_encoded += encoded.size()
	return {"roundtrips": 80 * scale, "input_bytes": total_input, "compressed_bytes": total_encoded}


func _regex(scale: int) -> Dictionary:
	var regex := RegEx.new()
	if regex.compile("([a-z]+)_([0-9]+)") != OK:
		return {"error": "Cannot compile benchmark expression"}
	var text := "item_100 segment_200 counter_300 ignored"
	var matches_total := 0
	for i in range(1500 * scale):
		var matches := regex.search_all(text)
		if matches.size() != 3 or matches[0].get_string(1) != "item" or matches[2].get_string(2) != "300":
			return {"error": "Regex result mismatch"}
		matches_total += matches.size()
	return {"searches": 1500 * scale, "matches": matches_total}


func _astar_3d(scale: int) -> Dictionary:
	var astar := AStar3D.new()
	var width := 14
	for z in range(width):
		for x in range(width):
			var point_id := z * width + x
			astar.add_point(point_id, Vector3(float(x), 0.0, float(z)))
	for z in range(width):
		for x in range(width):
			var point_id := z * width + x
			if x + 1 < width:
				astar.connect_points(point_id, point_id + 1)
			if z + 1 < width:
				astar.connect_points(point_id, point_id + width)
	var checksum := 0
	for i in range(240 * scale):
		var from_id := i % width
		var to_id := width * (width - 1) + (width - 1 - (i % width))
		var path := astar.get_id_path(from_id, to_id)
		if path.is_empty() or path[0] != from_id or path.back() != to_id:
			return {"error": "AStar3D path mismatch"}
		checksum += path.size()
	return {"nodes": width * width, "paths": 240 * scale, "checksum": checksum}


func _scene_reparent(tree: SceneTree, scale: int) -> Dictionary:
	var world := Node3D.new()
	tree.root.add_child(world)
	var left := Node3D.new()
	var right := Node3D.new()
	world.add_child(left)
	world.add_child(right)
	var nodes: Array[Node3D] = []
	for i in range(400 * scale):
		var node := Node3D.new()
		node.name = "Moving%d" % i
		left.add_child(node)
		nodes.append(node)
	var moves := 0
	for round_index in range(6):
		var target := right if round_index % 2 == 0 else left
		for node in nodes:
			node.reparent(target, false)
			if node.get_parent() != target:
				world.free()
				return {"error": "Node reparent mismatch"}
			moves += 1
	if left.get_child_count() != nodes.size() or right.get_child_count() != 0:
		world.free()
		return {"error": "Node ownership mismatch after reparent"}
	world.free()
	return {"nodes": nodes.size(), "reparent_operations": moves}


func _resource_roundtrip(scale: int) -> Dictionary:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(1.0, 1.0))
	var path := "user://stress_resource_%d.tres" % OS.get_process_id()
	if ResourceSaver.save(curve, path) != OK:
		return {"error": "ResourceSaver could not write stress curve"}
	var samples := 0.0
	var problem := ""
	for i in range(70 * scale):
		var restored := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Curve
		if restored == null or restored.get_point_count() != 2:
			problem = "ResourceLoader returned invalid curve"
			break
		var sample := restored.sample(0.5)
		if absf(sample - 0.5) > 0.05:
			problem = "Resource data changed after deserialization"
			break
		samples += sample
	var removed := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if problem != "":
		return {"error": problem}
	if removed != OK:
		return {"error": "Could not remove stress resource"}
	return {"loads": 70 * scale, "checksum": samples}


func _contention_worker(iterations: int) -> int:
	for i in range(iterations):
		_contention_mutex.lock()
		_contention_counter += 1
		_contention_mutex.unlock()
	return iterations


func _thread_contention(scale: int) -> Dictionary:
	_contention_counter = 0
	var workers: Array[Thread] = []
	var count := mini(8, maxi(2, OS.get_processor_count()))
	var iterations := 5000 * scale
	for i in range(count):
		var worker := Thread.new()
		if worker.start(Callable(self, "_contention_worker").bind(iterations)) != OK:
			for running in workers:
				running.wait_to_finish()
			return {"error": "Cannot start contention worker"}
		workers.append(worker)
	var completed := 0
	for worker in workers:
		completed += int(worker.wait_to_finish())
	if completed != count * iterations or _contention_counter != completed:
		return {"error": "Lost updates under mutex contention"}
	return {"workers": count, "lock_operations": completed, "checksum": _contention_counter}


func _physics_queries_2d(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var world := Node2D.new()
	tree.root.add_child(world)
	var floor_body := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(1000.0, 2.0)
	collision.shape = rectangle
	floor_body.add_child(collision)
	world.add_child(floor_body)
	await tree.physics_frame
	var state := world.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(Vector2(0.0, -20.0), Vector2(0.0, 20.0))
	var queries := 0
	var peak_physics_ms := 0.0
	for frame in range(frames):
		for i in range(50 * scale):
			var x := float((i + frame) % 500) - 250.0
			query.from = Vector2(x, -20.0)
			query.to = Vector2(x, 20.0)
			var hit := state.intersect_ray(query)
			if hit.is_empty():
				world.queue_free()
				await tree.process_frame
				return {"error": "Physics ray failed to hit known static body"}
			queries += 1
		await tree.physics_frame
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	world.queue_free()
	await tree.process_frame
	return {"queries": queries, "frames": frames, "peak_physics_ms": peak_physics_ms}


func _render_multimesh(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var world := Node3D.new()
	tree.root.add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 40.0, 80.0)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var light := DirectionalLight3D.new()
	world.add_child(light)
	var instances := 800 * scale
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = BoxMesh.new()
	multimesh.instance_count = instances
	for i in range(instances):
		var position := Vector3(float(i % 100) - 50.0, 0.0, float(i / 100) - float(instances / 200))
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, position))
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = multimesh
	world.add_child(batch)
	var peak_frame_ms := 0.0
	var peak_draw_calls := 0
	var peak_video_bytes := 0
	for i in range(frames):
		await tree.process_frame
		peak_frame_ms = maxf(peak_frame_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		peak_draw_calls = maxi(peak_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		peak_video_bytes = maxi(peak_video_bytes, int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))
	world.queue_free()
	await tree.process_frame
	return {"instances": instances, "frames": frames, "peak_frame_ms": peak_frame_ms, "peak_draw_calls": peak_draw_calls, "peak_video_memory_bytes": peak_video_bytes}
