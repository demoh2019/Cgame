extends RefCounted
## Deterministic CPU workloads for CanvasItem propagation and SceneTree dispatch.
## Each scenario is run in its own Godot process with RSS and timeout watchdogs.


func canvas_transform(tree: SceneTree, scale: int) -> Dictionary:
	var parent := Node2D.new()
	tree.root.add_child(parent)
	parent.set_oversampling_with_scale(CanvasItem.OVERSAMPLING_WITH_SCALE_ENABLED)
	parent.scale = Vector2(2, 2)

	# A moving parent invalidates a wide, two-level 2D scene hierarchy.
	var count := mini(128 * scale, 4096)
	var leaves: Array[Node2D] = []
	leaves.resize(count)
	for i in range(count):
		var branch := Node2D.new()
		branch.position = Vector2(i, 1)
		parent.add_child(branch)
		var leaf := Node2D.new()
		leaf.position = Vector2(2, 3)
		branch.add_child(leaf)
		leaves[i] = leaf

	var mutation_usec := 0
	var recompute_usec := 0
	var checksum := 0.0
	var rounds := mini(24 * scale, 512)
	for pass_index in range(rounds):
		var elapsed := Time.get_ticks_usec()
		parent.position = Vector2(pass_index, float(pass_index) * 0.5)
		mutation_usec += Time.get_ticks_usec() - elapsed
		elapsed = Time.get_ticks_usec()

		# Reading every leaf makes the next invalidation a real full-tree
		# pass rather than an early exit due to already-dirty children.
		for i in range(count):
			var global_pos := leaves[i].global_position
			checksum += global_pos.x * 0.001
		recompute_usec += Time.get_ticks_usec() - elapsed

	var last := leaves[count - 1].global_position
	var expected_x := float(rounds - 1) + float(2 * (count + 1))
	if absf(last.x - expected_x) > 0.01 or is_nan(checksum) or is_inf(checksum):
		leaves.clear()
		parent.free()
		return {"error": "CanvasItem descendant transform propagation mismatch"}

	leaves.clear()
	parent.free()
	return {
		"branches": count, "canvas_nodes": count * 2 + 1,
		"transform_changes": rounds, "leaf_reads": count * rounds,
		"transform_mutation_ms": float(mutation_usec) / 1000.0,
		"global_transform_rebuild_ms": float(recompute_usec) / 1000.0,
		"checksum": checksum,
	}


func process_dispatch(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var parent := Node.new()
	tree.root.add_child(parent)
	var count := mini(300 * scale, 6000)

	# Plain native Nodes have no GDScript _process callback, so this captures
	# the engine's notification/dispatch overhead rather than script logic.
	for i in range(count):
		var node := Node.new()
		parent.add_child(node)
		node.set_process(true)
		node.set_physics_process(true)
		if (i & 1) == 0:
			node.set_process_internal(true)
		if i % 3 == 0:
			node.set_physics_process_internal(true)

	await tree.process_frame
	var frame_count := mini(frames, 180)
	var total_process_ms := 0.0
	var peak_process_ms := 0.0
	var peak_physics_ms := 0.0
	var started := Time.get_ticks_usec()
	for frame in range(frame_count):
		await tree.process_frame
		var process_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		total_process_ms += process_ms
		peak_process_ms = maxf(peak_process_ms, process_ms)
		peak_physics_ms = maxf(peak_physics_ms, physics_ms)
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0

	parent.free()
	return {
		"nodes": count, "frames": frame_count,
		"elapsed_ms": elapsed_ms,
		"avg_process_ms": total_process_ms / float(frame_count),
		"peak_process_ms": peak_process_ms,
		"peak_physics_ms": peak_physics_ms,
		"checksum": count * frame_count,
	}
