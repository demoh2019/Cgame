extends SceneTree
## Deterministic, one-scenario-per-process Godot stress workload.
## Use run.py for watchdogs, repeatability, reporting and RSS limits.

signal sample_signal(value: int)

const PREFIX := "STRESS_RESULT:"
const CASES := [
	"containers", "strings", "script_vm", "math", "signals",
	"scene_tree", "packed_scene", "images", "json", "stream",
	"file_io", "threads", "physics_2d", "physics_3d",
	"memory_churn", "astar_grid", "tweens", "audio_buffers",
	"variant_codec", "render_2d", "render_3d",
	"compression", "regex", "astar_3d", "scene_reparent",
	"resource_roundtrip", "thread_contention", "physics_queries_2d",
	"render_multimesh",
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
		"audio_buffers":
			return _audio_buffers(scale)
		"variant_codec":
			return _variant_codec(scale)
		"tweens":
			return await _tweens(scale, frames)
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
	var additional := preload("res://extra_stress.gd").new()
	return await additional.run_case(test_case, self, scale, frames, seed)


func _on_sample(value: int) -> void:
	signal_total += value


func _sample_percentiles(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {}
	values.sort()
	var size := values.size()
	return {
		"p50": values[clampi(ceili(float(size) * 0.50) - 1, 0, size - 1)],
		"p95": values[clampi(ceili(float(size) * 0.95) - 1, 0, size - 1)],
		"p99": values[clampi(ceili(float(size) * 0.99) - 1, 0, size - 1)],
		"max": values[size - 1],
	}


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
	var latency_samples: Array[float] = []
	for i in range(frames):
		await process_frame
		var sample_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		latency_samples.append(sample_ms)
		peak_frame_ms = maxf(peak_frame_ms, sample_ms)
	world.queue_free()
	await process_frame
	return {"active_tweens": count, "frames": frames, "peak_frame_ms": peak_frame_ms, "frame_latency_ms": _sample_percentiles(latency_samples)}


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
	var latency_samples: Array[float] = []
	var peak_pairs := 0
	for i in range(frames):
		await physics_frame
		var sample_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		latency_samples.append(sample_ms)
		peak_physics_ms = maxf(peak_physics_ms, sample_ms)
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)))
	world.queue_free()
	await process_frame
	return {"bodies": length, "physics_frames": frames, "peak_physics_ms": peak_physics_ms, "peak_collision_pairs": peak_pairs, "physics_latency_ms": _sample_percentiles(latency_samples)}


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
	var latency_samples: Array[float] = []
	var peak_pairs := 0
	for i in range(frames):
		await physics_frame
		var sample_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		latency_samples.append(sample_ms)
		peak_physics_ms = maxf(peak_physics_ms, sample_ms)
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
	world.queue_free()
	await process_frame
	return {"bodies": length, "physics_frames": frames, "peak_physics_ms": peak_physics_ms, "peak_collision_pairs": peak_pairs, "physics_latency_ms": _sample_percentiles(latency_samples)}


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
	var latency_samples: Array[float] = []
	var peak_draw_calls := 0
	var peak_video_memory := 0
	for i in range(frames):
		await process_frame
		var sample_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		latency_samples.append(sample_ms)
		peak_frame_ms = maxf(peak_frame_ms, sample_ms)
		peak_draw_calls = maxi(peak_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		peak_video_memory = maxi(peak_video_memory, int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))
	world.queue_free()
	await process_frame
	return {"sprites": 600 * scale, "frames": frames, "peak_frame_ms": peak_frame_ms, "peak_draw_calls": peak_draw_calls, "peak_video_memory_bytes": peak_video_memory, "frame_latency_ms": _sample_percentiles(latency_samples)}


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
	var latency_samples: Array[float] = []
	var peak_draw_calls := 0
	var peak_video_memory := 0
	for i in range(frames):
		await process_frame
		var sample_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		latency_samples.append(sample_ms)
		peak_frame_ms = maxf(peak_frame_ms, sample_ms)
		peak_draw_calls = maxi(peak_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		peak_video_memory = maxi(peak_video_memory, int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))
	world.queue_free()
	await process_frame
	return {"meshes": 200 * scale, "frames": frames, "peak_frame_ms": peak_frame_ms, "peak_draw_calls": peak_draw_calls, "peak_video_memory_bytes": peak_video_memory, "frame_latency_ms": _sample_percentiles(latency_samples)}
