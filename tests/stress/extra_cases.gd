extends RefCounted
## Isolated file-system and scene-lifetime stress cases.


func run_case(test_case: String, scale: int, frames: int, tree: SceneTree) -> Dictionary:
	match test_case:
		"small_file_io":
			return _small_file_io(scale)
		"scene_churn":
			return await _scene_churn(scale, frames, tree)
	return {"error": "Unknown extended stress case"}


func _small_file_io(scale: int) -> Dictionary:
	var directory := "user://stress_small_files"
	var absolute_dir := ProjectSettings.globalize_path(directory)
	if DirAccess.make_dir_recursive_absolute(absolute_dir) != OK:
		return {"error": "Could not create stress directory"}
	var count := 100 * scale
	var started := Time.get_ticks_usec()
	for i in range(count):
		var path := "%s/item_%d.bin" % [directory, i]
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return {"error": "Could not write small file"}
		file.store_32(i)
		file.store_32(i ^ 0x55aa55aa)
		file.close()
	var write_ms := float(Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	var checksum := 0
	var error := ""
	for i in range(count):
		var path := "%s/item_%d.bin" % [directory, i]
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			error = "Could not read small file"
			break
		if file.get_32() != i or file.get_32() != (i ^ 0x55aa55aa):
			error = "Small file roundtrip mismatch"
			file.close()
			break
		file.close()
		checksum += 8
	var read_ms := float(Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	for i in range(count):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/item_%d.bin" % [directory, i]))
	DirAccess.remove_absolute(absolute_dir)
	var cleanup_ms := float(Time.get_ticks_usec() - started) / 1000.0
	if not error.is_empty():
		return {"error": error}
	return {"files": count, "bytes_written_and_read": checksum * 2,
		"phases_ms": {"write": write_ms, "read": read_ms, "cleanup": cleanup_ms}}


func _scene_churn(scale: int, frames: int, tree: SceneTree) -> Dictionary:
	var parent := Node2D.new()
	tree.root.add_child(parent)
	var nodes_per_cycle := 10 * scale
	var peak_frame_ms := 0.0
	var started := Time.get_ticks_usec()
	for cycle in range(frames):
		for i in range(nodes_per_cycle):
			var node := Node2D.new()
			parent.add_child(node)
		await tree.process_frame
		peak_frame_ms = maxf(peak_frame_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		for node in parent.get_children():
			node.queue_free()
		await tree.process_frame
	var workload_ms := float(Time.get_ticks_usec() - started) / 1000.0
	parent.queue_free()
	await tree.process_frame
	return {"nodes_created": nodes_per_cycle * frames, "frames": frames * 2,
		"peak_frame_ms": peak_frame_ms, "phases_ms": {"create_process_free": workload_ms}}
