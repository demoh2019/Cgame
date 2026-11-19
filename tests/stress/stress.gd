extends SceneTree
## Deterministic, one-scenario-per-process Godot stress workload.
## Use run.py for watchdogs, repeatability, reporting and RSS limits.

signal sample_signal(value: int)

const PREFIX := "STRESS_RESULT:"
const ExtraStress := preload("res://extra_stress.gd")
const CASES := [
	"containers", "strings", "script_vm", "math", "signals",
	"scene_tree", "packed_scene", "images", "json", "stream",
	"file_io", "threads", "physics_2d", "physics_3d",
	"memory_churn", "astar_grid", "astar_graph", "tweens", "audio_buffers",
	"variant_codec", "packet_stream", "ui_layout", "render_2d", "render_3d",
	"resource_load",
	"input_map",
	"transform_hierarchy",
	"node_paths", "regex", "compression", "hashing",
	"resource_io", "astar_3d", "thread_contention",
	"geometry_2d", "mesh_build", "input_dispatch", "image_codec", "group_calls",
	"packed_arrays", "sorting", "animation_tracks", "physics_raycast_2d",
	"physics_raycast_3d", "render_multimesh_3d",
]

var signal_total: int = 0


func _initialize() -> void:
	call_deferred("_execute")


func _execute() -> void:
	var selected := ""
	var scale := 1
	var frames := 30
	var seed := 12345
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			selected = argument.trim_prefix("--case=")
		elif argument.begins_with("--scale="):
			scale = int(argument.trim_prefix("--scale="))
		elif argument.begins_with("--frames="):
			frames = int(argument.trim_prefix("--frames="))
		elif argument.begins_with("--seed="):
			seed = int(argument.trim_prefix("--seed="))

	if not CASES.has(selected) or scale < 1 or scale > 1000 or frames < 1 or frames > 100000:
		printerr("Invalid stress arguments: case=", selected, ", scale=", scale, ", frames=", frames)
		quit(2)
		return

	var before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var started := Time.get_ticks_usec()
	var detail: Dictionary = await _run_case(selected, scale, frames, seed)
	var duration_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var after := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var failed := detail.has("error")
	var result := {
		"case": selected,
		"scale": scale,
		"frames": frames,
		"seed": seed,
		"duration_ms": duration_ms,
		"engine_memory_before_bytes": before,
		"engine_memory_after_bytes": after,
		"detail": detail,
	}
	print(PREFIX + JSON.stringify(result))
	quit(1 if failed else 0)


func _run_case(test_case: String, scale: int, frames: int, seed: int) -> Dictionary:
	match test_case:
		"containers":
			var length := 20000 * scale
			var array: Array[int] = []
			var dictionary: Dictionary = {}
			array.resize(length)
			for i in range(length):
				array[i] = i
				dictionary[i] = i ^ 0x5555
			var checksum := 0
			for i in range(length * 3):
				var index := (i * 4099) % length
				checksum = (checksum + array[index] + int(dictionary[index])) & 0x7fffffff
			dictionary.clear()
			array.clear()
			return {"operations": length * 5, "checksum": checksum}
		"strings":
			var checksum := 0
			for i in range(10000 * scale):
				var value := "stress:%08d:Red,Green,Blue" % i
				var split := value.split(":")
				checksum += split[1].length() + value.find("Green") + value.to_upper().length()
			return {"iterations": 10000 * scale, "checksum": checksum}
		"script_vm":
			var accumulator := 0
			var values: Array[int] = [3, 7, 11, 17, 23, 31, 41]
			for i in range(500000 * scale):
				var index := i % values.size()
				accumulator = (accumulator + values[index] * (i & 255)) & 0x7fffffff
				values[index] = (values[index] + 3) & 65535
			return {"operations": 500000 * scale, "checksum": accumulator}
		"math":
			var accumulator := 0.0
			var vec := Vector3(3.0, 4.0, 5.0)
			for i in range(50000 * scale):
				var rhs := Vector3(float(i & 63) + 1.0, 2.0, 3.0)
				vec = (vec + rhs.cross(Vector3.UP) * 0.0001).normalized() * 7.0
				accumulator += vec.dot(rhs)
			return {"operations": 50000 * scale, "checksum": accumulator}
		"signals":
			signal_total = 0
			sample_signal.connect(_on_sample)
			for i in range(50000 * scale):
				sample_signal.emit(i & 7)
			sample_signal.disconnect(_on_sample)
			return {"emissions": 50000 * scale, "checksum": signal_total}
		"scene_tree":
			var parent := Node.new()
			root.add_child(parent)
			var length := 1200 * scale
			for i in range(length):
				var node := Node2D.new()
				node.name = "StressNode%d" % i
				parent.add_child(node)
				node.add_to_group("stress_nodes")
			var found := parent.find_children("StressNode*", "Node2D", true, false)
			var total := found.size() + get_nodes_in_group("stress_nodes").size()
			parent.free()
			return {"nodes": length, "checksum": total}
		"packed_scene":
			var prototype := Node2D.new()
			for i in range(24):
				var child := Node2D.new()
				child.name = "Part%d" % i
				prototype.add_child(child)
				child.owner = prototype
			var packed := PackedScene.new()
			if packed.pack(prototype) != OK:
				prototype.free()
				return {"error": "Could not pack prototype"}
			prototype.free()
			var checksum := 0
			for i in range(150 * scale):
				var instance := packed.instantiate()
				if instance == null:
					return {"error": "Could not instantiate PackedScene"}
				checksum += instance.get_child_count()
				instance.free()
			return {"instances": 150 * scale, "checksum": checksum}
		"images":
			var checksum := 0
			for i in range(200 * scale):
				var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
				img.fill(Color(float(i & 255) / 255.0, 0.5, 0.25, 1.0))
				img.set_pixel(i % 128, int(i / 128) % 128, Color.WHITE)
				checksum += img.get_data().size()
			return {"images": 200 * scale, "checksum": checksum}
		"json":
			var objects: Array[Dictionary] = []
			for i in range(500 * scale):
				objects.append({"id": i, "name": "object_%d" % i, "position": [i, i + 1, i + 2]})
			var checksum := 0
			for i in range(10):
				var encoded := JSON.stringify(objects)
				var decoded = JSON.parse_string(encoded)
				if not (decoded is Array) or decoded.size() != objects.size():
					return {"error": "JSON roundtrip mismatch"}
				checksum += encoded.length()
			return {"records": objects.size(), "checksum": checksum}
		"stream":
			var peer := StreamPeerBuffer.new()
			var length := 20000 * scale
			for i in range(length):
				peer.put_32(i)
			peer.seek(0)
			var checksum := 0
			for i in range(length):
				var received := peer.get_32()
				if received != i:
					return {"error": "Stream corruption at %d" % i}
				checksum = (checksum + received) & 0x7fffffff
			return {"messages": length, "checksum": checksum}
		"file_io":
			return _file_io(scale)
		"threads":
			return _threads(scale, seed)
		"astar_grid":
			return _astar_grid(scale)
		"astar_graph":
			return _astar_graph(scale)
		"audio_buffers":
			return _audio_buffers(scale)
		"variant_codec":
			return _variant_codec(scale)
		"tweens":
			return await _tweens(scale, frames)
		"packet_stream":
			return _packet_stream(scale)
		"ui_layout":
			return await _ui_layout(scale, frames)
		"physics_2d":
			return await _physics_2d(scale, frames)
		"physics_3d":
			return await _physics_3d(scale, frames)
		"memory_churn":
			return await _memory_churn(scale)
		"render_2d":
			return await _render_2d(scale, frames)
		"render_3d":
			return await _render_3d(scale, frames)
		"resource_load":
			return _resource_load(scale)
		"input_map":
			return _input_map(scale)
		"transform_hierarchy":
			return _transform_hierarchy(scale)
		"node_paths":
			return _node_paths(scale)
		"regex":
			return _regex(scale)
		"compression":
			return _compression(scale)
		"hashing":
			return _hashing(scale)
		"resource_io":
			return _resource_io(scale)
		"astar_3d":
			return _astar_3d(scale)
		"thread_contention":
			return _thread_contention(scale)
		"geometry_2d", "mesh_build", "input_dispatch", "image_codec", "group_calls":
			return ExtraStress.new().run(test_case, self, scale)
		"packed_arrays":
			return _packed_arrays(scale)
		"sorting":
			return _sorting(scale)
		"animation_tracks":
			return _animation_tracks(scale)
		"physics_raycast_2d":
			return await _physics_raycast_2d(scale)
		"physics_raycast_3d":
			return await _physics_raycast_3d(scale)
		"render_multimesh_3d":
			return await _render_multimesh_3d(scale, frames)
	return {"error": "Unhandled case"}


func _on_sample(value: int) -> void:
	signal_total += value


func _file_io(scale: int) -> Dictionary:
	var path := "user://stress_file_io.bin"
	var payload := PackedByteArray()
	payload.resize(1024 * 1024)
	for i in range(payload.size()):
		payload[i] = i & 255
	var checksum := 0
	for i in range(8 * scale):
		var output := FileAccess.open(path, FileAccess.WRITE)
		if output == null:
			return {"error": "Could not open file for write"}
		output.store_buffer(payload)
		output.close()
		var input := FileAccess.open(path, FileAccess.READ)
		if input == null:
			return {"error": "Could not open file for read"}
		var data := input.get_buffer(payload.size())
		input.close()
		if data.size() != payload.size() or data[0] != 0 or data[data.size() - 1] != 255:
			return {"error": "File roundtrip failed"}
		checksum += data.size()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return {"bytes_written_and_read": checksum * 2, "checksum": checksum}


func _thread_task(iterations: int, initial: int) -> int:
	var accumulator := initial & 0x7fffffff
	for i in range(iterations):
		accumulator = (accumulator * 1664525 + 1013904223 + i) & 0x7fffffff
	return accumulator


func _threads(scale: int, seed: int) -> Dictionary:
	var workers: Array[Thread] = []
	var count := mini(16, maxi(2, OS.get_processor_count()))
	for i in range(count):
		var worker := Thread.new()
		if worker.start(Callable(self, "_thread_task").bind(100000 * scale, seed + i)) != OK:
			for active in workers:
				active.wait_to_finish()
			return {"error": "Could not start worker thread"}
		workers.append(worker)
	var checksum := 0
	for worker in workers:
		checksum = (checksum + int(worker.wait_to_finish())) & 0x7fffffff
	return {"workers": count, "operations": count * 100000 * scale, "checksum": checksum}


func _astar_grid(scale: int) -> Dictionary:
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, 64, 64)
	astar.cell_size = Vector2.ONE
	astar.update()
	for y in range(64):
		if y != 32:
			astar.set_point_solid(Vector2i(32, y))
	var checksum := 0
	for i in range(100 * scale):
		var origin := Vector2i(i % 20, (i * 7) % 64)
		var destination := Vector2i(63 - (i % 20), 63 - ((i * 11) % 64))
		var path := astar.get_id_path(origin, destination)
		if path.is_empty() or path[0] != origin or path.back() != destination:
			return {"error": "AStar path missing or incorrect"}
		checksum += path.size()
	return {"searches": 100 * scale, "checksum": checksum}


func _audio_buffers(scale: int) -> Dictionary:
	var checksum := 0
	for k in range(50 * scale):
		var wave := PackedByteArray()
		wave.resize(16384)
		for i in range(8192):
			wave[i * 2] = (i + k) & 255
			wave[i * 2 + 1] = (i >> 8) & 255
		var audio := AudioStreamWAV.new()
		audio.format = AudioStreamWAV.FORMAT_16_BITS
		audio.mix_rate = 44100
		audio.stereo = false
		audio.data = wave
		if audio.get_length() <= 0.0:
			return {"error": "Invalid audio buffer length"}
		checksum += audio.data.size()
	return {"buffers": 50 * scale, "checksum": checksum}


func _variant_codec(scale: int) -> Dictionary:
	var value := {
		"names": PackedStringArray(["scene", "physics", "render"]),
		"positions": PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)]),
		"payload": PackedByteArray([1, 2, 3, 4, 5]),
		"nested": {"flag": true, "count": 42},
	}
	var checksum := 0
	for i in range(2000 * scale):
		var encoded := var_to_bytes(value)
		var decoded = bytes_to_var(encoded)
		if not (decoded is Dictionary) or decoded["nested"]["count"] != 42:
			return {"error": "Variant roundtrip mismatch"}
		checksum += encoded.size()
	return {"roundtrips": 2000 * scale, "checksum": checksum}


func _tweens(scale: int, frames: int) -> Dictionary:
	var world := Node2D.new()
	root.add_child(world)
	var count := 300 * scale
	for i in range(count):
		var node := Node2D.new()
		world.add_child(node)
		var tween := node.create_tween()
		tween.set_loops()
		tween.tween_property(node, "position", Vector2(float(i & 31), 20.0), 0.1)
		tween.tween_property(node, "position", Vector2.ZERO, 0.1)
	var peak_frame_ms := 0.0
	for i in range(frames):
		await process_frame
		peak_frame_ms = maxf(peak_frame_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	world.queue_free()
	await process_frame
	return {"active_tweens": count, "frames": frames, "peak_frame_ms": peak_frame_ms}



func _packet_stream(scale: int) -> Dictionary:
	# Exercises the framing and ring-buffer path, including boundary sizes.
	var checksum := 0
	var lengths := PackedInt32Array([1, 7, 64, 1024, 8191, 16384])
	for i in range(120 * scale):
		var length := lengths[i % lengths.size()]
		var payload := PackedByteArray()
		payload.resize(length)
		for j in range(length):
			payload[j] = (i * 17 + j * 29) & 255
		var memory_stream := StreamPeerBuffer.new()
		var packet_peer := PacketPeerStream.new()
		packet_peer.input_buffer_max_size = 32768
		packet_peer.output_buffer_max_size = 32768
		packet_peer.stream_peer = memory_stream
		if packet_peer.put_packet(payload) != OK:
			return {"error": "Packet write failed at %d" % i}
		memory_stream.seek(0)
		var received := packet_peer.get_packet()
		if packet_peer.get_packet_error() != OK or received != payload:
			return {"error": "Packet corruption at %d (%d bytes)" % [i, length]}
		checksum += received.size()
	return {"packets": 120 * scale, "bytes": checksum, "checksum": checksum}


func _ui_layout(scale: int, frames: int) -> Dictionary:
	var viewport_ui := PanelContainer.new()
	viewport_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(viewport_ui)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(800, 600)
	viewport_ui.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 12
	scroll.add_child(grid)
	var length := 250 * scale
	for i in range(length):
		var button := Button.new()
		button.text = "Test Button %05d" % i
		button.custom_minimum_size = Vector2(120, 24)
		grid.add_child(button)
	var peak_frame_ms := 0.0
	for frame in range(frames):
		if frame % 8 == 0:
			grid.columns = 8 + (frame % 16)
		await process_frame
		peak_frame_ms = maxf(peak_frame_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	viewport_ui.queue_free()
	await process_frame
	return {"controls": length, "frames": frames, "peak_frame_ms": peak_frame_ms}



func _physics_2d(scale: int, frames: int) -> Dictionary:
	var world := Node2D.new()
	root.add_child(world)
	var circle := CircleShape2D.new()
	circle.radius = 4.0
	var length := 180 * scale
	for i in range(length):
		var body := RigidBody2D.new()
		body.position = Vector2(float(i % 40) * 7.0, float(i / 40) * 7.0)
		var collider := CollisionShape2D.new()
		collider.shape = circle
		body.add_child(collider)
		world.add_child(body)
	var peak_physics_ms := 0.0
	var peak_pairs := 0
	for i in range(frames):
		await physics_frame
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)))
	world.queue_free()
	await process_frame
	return {"bodies": length, "physics_frames": frames, "peak_physics_ms": peak_physics_ms, "peak_collision_pairs": peak_pairs}


func _physics_3d(scale: int, frames: int) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var sphere := SphereShape3D.new()
	sphere.radius = 0.6
	var length := 100 * scale
	for i in range(length):
		var body := RigidBody3D.new()
		body.position = Vector3(float(i % 20), float(i / 20), 0.0)
		var collider := CollisionShape3D.new()
		collider.shape = sphere
		body.add_child(collider)
		world.add_child(body)
	var peak_physics_ms := 0.0
	var peak_pairs := 0
	for i in range(frames):
		await physics_frame
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
	world.queue_free()
	await process_frame
	return {"bodies": length, "physics_frames": frames, "peak_physics_ms": peak_physics_ms, "peak_collision_pairs": peak_pairs}


func _memory_churn(scale: int) -> Dictionary:
	var readings: Array[int] = []
	for cycle in range(12):
		var allocations: Array[PackedByteArray] = []
		for i in range(300 * scale):
			var block := PackedByteArray()
			block.resize(4096)
			block[0] = i & 255
			allocations.append(block)
		allocations.clear()
		await process_frame
		readings.append(int(Performance.get_monitor(Performance.MEMORY_STATIC)))
	var retained := readings.back() - readings[2]
	return {"cycles": readings.size(), "sample_bytes": readings, "retained_growth_bytes": retained}


func _render_2d(scale: int, frames: int) -> Dictionary:
	var world := Node2D.new()
	root.add_child(world)
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.4, 0.6, 0.8))
	var shared_texture := ImageTexture.create_from_image(image)
	for i in range(600 * scale):
		var sprite := Sprite2D.new()
		sprite.texture = shared_texture
		sprite.position = Vector2(float(i % 120) * 9.0, float(i / 120) * 9.0)
		world.add_child(sprite)
	var peak_frame_ms := 0.0
	var peak_draw_calls := 0
	var peak_video_memory := 0
	for i in range(frames):
		await process_frame
		peak_frame_ms = maxf(peak_frame_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		peak_draw_calls = maxi(peak_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		peak_video_memory = maxi(peak_video_memory, int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))
	world.queue_free()
	await process_frame
	return {"sprites": 600 * scale, "frames": frames, "peak_frame_ms": peak_frame_ms, "peak_draw_calls": peak_draw_calls, "peak_video_memory_bytes": peak_video_memory}


func _render_3d(scale: int, frames: int) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 30, 60)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var light := DirectionalLight3D.new()
	world.add_child(light)
	var box := BoxMesh.new()
	for i in range(200 * scale):
		var mesh := MeshInstance3D.new()
		mesh.mesh = box
		mesh.position = Vector3(float(i % 40) - 20.0, 0.0, float(i / 40) - 10.0)
		world.add_child(mesh)
	var peak_frame_ms := 0.0
	var peak_draw_calls := 0
	var peak_video_memory := 0
	for i in range(frames):
		await process_frame
		peak_frame_ms = maxf(peak_frame_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		peak_draw_calls = maxi(peak_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		peak_video_memory = maxi(peak_video_memory, int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))
	world.queue_free()
	await process_frame
	return {"meshes": 200 * scale, "frames": frames, "peak_frame_ms": peak_frame_ms, "peak_draw_calls": peak_draw_calls, "peak_video_memory_bytes": peak_video_memory}


## Additional cross-subsystem workloads. Each one has an explicit integrity check.

func _node_paths(scale: int) -> Dictionary:
	var group := Node.new()
	root.add_child(group)
	var paths: Array[NodePath] = []
	var count := 400 * scale
	for i in range(count):
		var child := Node.new()
		child.name = "Target%d" % i
		group.add_child(child)
		paths.append(NodePath("Target%d" % i))
	var started := Time.get_ticks_usec()
	var found := 0
	for i in range(count * 10):
		if group.get_node_or_null(paths[i % count]) != null:
			found += 1
	var lookup_ms := float(Time.get_ticks_usec() - started) / 1000.0
	group.free()
	if found != count * 10:
		return {"error": "NodePath lookup count mismatch"}
	return {"nodes": count, "lookups": found, "lookup_ms": lookup_ms}


func _regex(scale: int) -> Dictionary:
	var pattern := RegEx.new()
	if pattern.compile("item_[0-9]{4}:[A-Z]+") != OK:
		return {"error": "RegEx could not compile"}
	var matches_found := 0
	for i in range(400 * scale):
		var value := "item_%04d:ALPHA item_%04d:BETA no-match" % [i % 10000, (i + 1) % 10000]
		var matches := pattern.search_all(value)
		if matches.size() != 2:
			return {"error": "RegEx match count mismatch"}
		matches_found += matches.size()
	return {"inputs": 400 * scale, "matches": matches_found}


func _compression(scale: int) -> Dictionary:
	var data := PackedByteArray()
	data.resize(256 * 1024)
	for i in range(data.size()):
		data[i] = (i * 31 + (i >> 3)) & 255
	var compressed_bytes := 0
	for i in range(35 * scale):
		var compressed := data.compress(FileAccess.COMPRESSION_ZSTD)
		if compressed.is_empty():
			return {"error": "Zstd compression failed"}
		var restored := compressed.decompress(data.size(), FileAccess.COMPRESSION_ZSTD)
		if restored != data:
			return {"error": "Compressed payload differs after decompression"}
		compressed_bytes += compressed.size()
	return {"roundtrips": 35 * scale, "source_bytes": data.size(), "total_compressed_bytes": compressed_bytes}


func _hashing(scale: int) -> Dictionary:
	var bytes := PackedByteArray()
	bytes.resize(64 * 1024)
	for i in range(bytes.size()):
		bytes[i] = (i * 17 + (i >> 5)) & 255
	var first_digest := PackedByteArray()
	for i in range(120 * scale):
		var context := HashingContext.new()
		if context.start(HashingContext.HASH_SHA256) != OK:
			return {"error": "Could not initialize SHA-256 context"}
		if context.update(bytes) != OK:
			return {"error": "Could not hash input"}
		var digest := context.finish()
		if digest.size() != 32:
			return {"error": "Unexpected SHA-256 digest size"}
		if i == 0:
			first_digest = digest
		elif digest != first_digest:
			return {"error": "Unstable hash digest"}
	return {"hashes": 120 * scale, "bytes_per_hash": bytes.size(), "digest_prefix": first_digest.hex_encode().substr(0, 8)}


func _resource_io(scale: int) -> Dictionary:
	var path := "user://stress_resource_io.tres"
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(1.0, 1.0))
	var completed := 0
	var failure := ""
	for i in range(20 * scale):
		if ResourceSaver.save(curve, path) != OK:
			failure = "ResourceSaver failed"
			break
		var loaded := ResourceLoader.load(path, "Curve", ResourceLoader.CACHE_MODE_IGNORE) as Curve
		if loaded == null or loaded.get_point_count() != 2:
			failure = "ResourceLoader failed to restore Curve"
			break
		completed += 1
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not failure.is_empty():
		return {"error": failure}
	return {"roundtrips": completed, "resource_type": "Curve"}


func _astar_3d(scale: int) -> Dictionary:
	var finder := AStar3D.new()
	const SIDE := 20
	for y in range(SIDE):
		for x in range(SIDE):
			var point_id := y * SIDE + x
			finder.add_point(point_id, Vector3(x, 0.0, y))
			if x > 0:
				finder.connect_points(point_id, point_id - 1)
			if y > 0:
				finder.connect_points(point_id, point_id - SIDE)
	var checksum := 0
	for i in range(100 * scale):
		var path := finder.get_id_path(0, SIDE * SIDE - 1)
		if path.is_empty() or path[0] != 0 or path.back() != SIDE * SIDE - 1:
			return {"error": "AStar3D path incorrect"}
		checksum += path.size()
	return {"vertices": SIDE * SIDE, "searches": 100 * scale, "checksum": checksum}


var contention_lock := Mutex.new()
var contention_counter: int = 0


func _contention_worker(operations: int) -> void:
	for i in range(operations):
		contention_lock.lock()
		contention_counter += 1
		contention_lock.unlock()


func _thread_contention(scale: int) -> Dictionary:
	var workers: Array[Thread] = []
	var count := mini(8, maxi(2, OS.get_processor_count()))
	var operations := 10000 * scale
	contention_counter = 0
	for i in range(count):
		var worker := Thread.new()
		if worker.start(Callable(self, "_contention_worker").bind(operations)) != OK:
			for active in workers:
				active.wait_to_finish()
			return {"error": "Could not start contention worker"}
		workers.append(worker)
	for worker in workers:
		worker.wait_to_finish()
	if contention_counter != count * operations:
		return {"error": "Mutex-protected counter mismatch"}
	return {"workers": count, "lock_operations": contention_counter}


# Independently validated CPU/physics/GPU pressure scenarios.

func _packed_arrays(scale: int) -> Dictionary:
	var count := 50000 * scale
	var values := PackedFloat32Array()
	values.resize(count)
	for i in range(count):
		values[i] = float(i % 1000) * 0.125
	var raw := values.to_byte_array()
	var restored := raw.to_float32_array()
	if restored.size() != count:
		return {"error": "Packed float roundtrip size mismatch"}
	var checksum := 0.0
	for i in range(0, count, 37):
		if restored[i] != values[i]:
			return {"error": "Packed float roundtrip data mismatch"}
		checksum += restored[i]
	return {"elements": count, "bytes": raw.size(), "checksum": checksum}


func _sorting(scale: int) -> Dictionary:
	var count := 10000 * scale
	var values: Array[int] = []
	values.resize(count)
	for i in range(count):
		values[i] = count - 1 - i
	values.sort()
	var checksum := 0
	for i in range(count * 2):
		var target := (i * 4099) % count
		var found := values.bsearch(target)
		if found >= count or values[found] != target:
			return {"error": "Binary search mismatch"}
		checksum = (checksum + found) & 0x7fffffff
	return {"elements": count, "searches": count * 2, "checksum": checksum}


func _animation_tracks(scale: int) -> Dictionary:
	var world := Node2D.new()
	root.add_child(world)
	var animated := Node2D.new()
	animated.name = "Animated"
	world.add_child(animated)
	var player := AnimationPlayer.new()
	world.add_child(player)
	player.root_node = NodePath("..")
	var animation := Animation.new()
	animation.length = 1.0
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath("Animated:position"))
	animation.track_insert_key(track, 0.0, Vector2.ZERO)
	animation.track_insert_key(track, 1.0, Vector2(100, 0))
	var library := AnimationLibrary.new()
	if library.add_animation("move", animation) != OK:
		world.free()
		return {"error": "AnimationLibrary registration failed"}
	if player.add_animation_library("", library) != OK:
		world.free()
		return {"error": "AnimationPlayer registration failed"}
	player.play("move")
	var checksum := 0.0
	for i in range(1000 * scale):
		player.seek(float(i % 100) / 100.0, true)
		checksum += animated.position.x
	world.free()
	if checksum <= 0:
		return {"error": "AnimationPlayer did not update animated track"}
	return {"seeks": 1000 * scale, "checksum": checksum}


func _physics_raycast_2d(scale: int) -> Dictionary:
	var world := Node2D.new()
	root.add_child(world)
	var shape := CircleShape2D.new()
	shape.radius = 2.0
	var bodies := 100 * scale
	for i in range(bodies):
		var body := StaticBody2D.new()
		body.position = Vector2(float(i) * 8.0, 0.0)
		var collider := CollisionShape2D.new()
		collider.shape = shape
		body.add_child(collider)
		world.add_child(body)
	await physics_frame
	await process_frame
	var hits := 0
	var started := Time.get_ticks_usec()
	for i in range(150 * scale):
		var y := float((i % 3) - 1)
		var query := PhysicsRayQueryParameters2D.create(Vector2(-5, y), Vector2(float(bodies) * 8.0 + 5.0, y))
		var hit := root.get_world_2d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			hits += 1
	var query_ms := float(Time.get_ticks_usec() - started) / 1000.0
	world.queue_free()
	await process_frame
	if hits == 0:
		return {"error": "Physics2D raycasts returned no hits"}
	return {"bodies": bodies, "queries": 150 * scale, "hits": hits, "query_ms": query_ms}


func _physics_raycast_3d(scale: int) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var shape := SphereShape3D.new()
	shape.radius = 2.0
	var bodies := 80 * scale
	for i in range(bodies):
		var body := StaticBody3D.new()
		body.position = Vector3(float(i) * 8.0, 0.0, 0.0)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		world.add_child(body)
	await physics_frame
	await process_frame
	var hits := 0
	var started := Time.get_ticks_usec()
	for i in range(150 * scale):
		var z := float((i % 3) - 1)
		var query := PhysicsRayQueryParameters3D.create(Vector3(-5, 0, z), Vector3(float(bodies) * 8.0 + 5.0, 0, z))
		var hit := root.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			hits += 1
	var query_ms := float(Time.get_ticks_usec() - started) / 1000.0
	world.queue_free()
	await process_frame
	if hits == 0:
		return {"error": "Physics3D raycasts returned no hits"}
	return {"bodies": bodies, "queries": 150 * scale, "hits": hits, "query_ms": query_ms}


func _render_multimesh_3d(scale: int, frames: int) -> Dictionary:
	# Requires a real display; dummy headless RenderingServer provides no GPU data.
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 75.0, 120.0)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var instances := 2000 * scale
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = BoxMesh.new()
	multimesh.instance_count = instances
	for i in range(instances):
		var pos := Vector3(float(i % 100) - 50.0, 0.0, float(i / 100) - float(instances / 200))
		multimesh.set_instance_transform(i, Transform3D(Basis(), pos))
	var node := MultiMeshInstance3D.new()
	node.multimesh = multimesh
	world.add_child(node)
	var frame_ms: Array[float] = []
	var peak_draw_calls := 0
	for i in range(frames):
		await process_frame
		frame_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		peak_draw_calls = maxi(peak_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	frame_ms.sort()
	var p95_frame_ms := frame_ms[maxi(0, int(ceil(float(frames) * 0.95)) - 1)]
	var peak_frame_ms := frame_ms.back()
	world.queue_free()
	await process_frame
	return {"instances": instances, "frames": frames, "p95_frame_ms": p95_frame_ms, "peak_frame_ms": peak_frame_ms, "peak_draw_calls": peak_draw_calls}


func _resource_load(scale: int) -> Dictionary:
	var path := "user://stress_generated_scene.tscn"
	var prototype := Node2D.new()
	for i in range(12):
		var child := Node2D.new()
		child.name = "Child%d" % i
		prototype.add_child(child)
		child.owner = prototype
	var scene := PackedScene.new()
	if scene.pack(prototype) != OK:
		prototype.free()
		return {"error": "Could not pack resource prototype"}
	prototype.free()
	if ResourceSaver.save(scene, path) != OK:
		return {"error": "ResourceSaver failed"}
	scene = null
	var checksum := 0
	for i in range(40 * scale):
		# Cache bypass deliberately exercises disk IO + text resource parsing.
		var loaded := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if not (loaded is PackedScene):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			return {"error": "ResourceLoader failed"}
		var instance := loaded.instantiate()
		if instance == null or instance.get_child_count() != 12:
			if instance != null:
				instance.free()
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			return {"error": "Loaded scene contents mismatch"}
		checksum += instance.get_child_count()
		instance.free()
	var cleanup := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if cleanup != OK:
		return {"error": "Could not remove generated test resource"}
	return {"reloads": 40 * scale, "checksum": checksum}


func _input_map(scale: int) -> Dictionary:
	var action := &"stress_generated_input_action"
	var event := InputEventKey.new()
	event.keycode = KEY_A
	event.pressed = true
	var matches := 0
	for i in range(3000 * scale):
		InputMap.add_action(action)
		InputMap.action_add_event(action, event)
		if not InputMap.event_is_action(event, action, true):
			InputMap.erase_action(action)
			return {"error": "Input action lookup mismatch"}
		matches += 1
		InputMap.erase_action(action)
	return {"registrations": matches, "checksum": matches}


func _transform_hierarchy(scale: int) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var nodes: Array[Node3D] = [world]
	var count := 300 * scale
	for i in range(count):
		var node := Node3D.new()
		node.position = Vector3(float(i & 7), 1.0, float(i & 15))
		nodes[int(i / 2)].add_child(node)
		nodes.append(node)
	var checksum := 0.0
	for pass_index in range(3):
		for i in range(1, nodes.size()):
			var node := nodes[i]
			node.position.x += 0.25
			checksum += node.global_position.x
	world.free()
	return {"nodes": count, "transform_reads": count * 3, "checksum": checksum}

func _astar_graph(scale: int) -> Dictionary:
	var graph := AStar2D.new()
	const WIDTH = 32
	for y in range(WIDTH):
		for x in range(WIDTH):
			var id := y * WIDTH + x
			graph.add_point(id, Vector2(x, y))
			if x > 0:
				graph.connect_points(id, id - 1)
			if y > 0:
				graph.connect_points(id, id - WIDTH)
	var checksum := 0
	for i in range(40 * scale):
		var start := i % WIDTH
		var finish := WIDTH * WIDTH - 1 - (i % WIDTH)
		var path := graph.get_id_path(start, finish)
		if path.is_empty() or path[0] != start or path[path.size() - 1] != finish:
			return {"error": "AStar graph path mismatch"}
		checksum += path.size()
	return {"vertices": WIDTH * WIDTH, "searches": 40 * scale, "checksum": checksum}
