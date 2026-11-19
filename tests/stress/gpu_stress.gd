extends SceneTree
## Real-display rendering stress suite. Run only via run_gpu.py; no dummy renderer.

const PREFIX := "STRESS_RESULT:"
const CASES := ["texture_upload", "canvas_overdraw", "multimesh_3d", "shadow_lights", "cpu_particles", "shader_variants"]


func _initialize() -> void:
	call_deferred("_execute")


func _execute() -> void:
	var selected := ""
	var scale := 1
	var frames := 60
	var seed := 12345
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):
			selected = arg.trim_prefix("--case=")
		elif arg.begins_with("--scale="):
			scale = int(arg.trim_prefix("--scale="))
		elif arg.begins_with("--frames="):
			frames = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--seed="):
			seed = int(arg.trim_prefix("--seed="))
	if not CASES.has(selected) or scale < 1 or scale > 1000 or frames < 1 or frames > 100000:
		printerr("Invalid rendering stress arguments")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		printerr("Rendering stress requires a display, not the headless dummy server")
		quit(2)
		return
	var started := Time.get_ticks_usec()
	var detail: Dictionary = await _run(selected, scale, frames)
	var result := {
		"case": selected, "scale": scale, "frames": frames, "seed": seed,
		"duration_ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"detail": detail,
	}
	print(PREFIX + JSON.stringify(result))
	quit(1 if detail.has("error") else 0)


func _frame_measurement(frames: int) -> Dictionary:
	# Discard startup shader compilation/warmup from steady-state frame latency.
	for i in range(12):
		await process_frame
	var samples: Array[float] = []
	var max_draw_calls := 0
	var max_video_memory := 0
	for i in range(frames):
		var tick := Time.get_ticks_usec()
		await process_frame
		samples.append(float(Time.get_ticks_usec() - tick) / 1000.0)
		max_draw_calls = maxi(max_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		max_video_memory = maxi(max_video_memory, int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))
	samples.sort()
	var count := samples.size()
	var hitches := 0
	for value in samples:
		if value > 33.333:
			hitches += 1
	return {
		"frame_p50_ms": samples[mini(count - 1, int(ceil(float(count) * 0.50)) - 1)],
		"frame_p95_ms": samples[mini(count - 1, int(ceil(float(count) * 0.95)) - 1)],
		"frame_p99_ms": samples[mini(count - 1, int(ceil(float(count) * 0.99)) - 1)],
		"frame_max_ms": samples.back(),
		"frame_hitches_over_33ms": hitches,
		"frame_samples": count,
		"max_draw_calls": max_draw_calls,
		"max_video_memory_bytes": max_video_memory,
	}


func _camera(world: Node3D) -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 35.0, 75.0)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true


func _run(selected: String, scale: int, frames: int) -> Dictionary:
	if selected == "texture_upload":
		var world := Node2D.new()
		root.add_child(world)
		var textures: Array[ImageTexture] = []
		var count := 64 * scale
		var allocation_start := Time.get_ticks_usec()
		for i in range(count):
			var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
			image.fill(Color(float(i & 255) / 255.0, 0.3, 0.7, 1.0))
			var texture := ImageTexture.create_from_image(image)
			textures.append(texture)
			var sprite := Sprite2D.new()
			sprite.texture = texture
			sprite.position = Vector2(float(i % 32) * 24.0, float(i / 32) * 24.0)
			world.add_child(sprite)
		var upload_ms := float(Time.get_ticks_usec() - allocation_start) / 1000.0
		var detail: Dictionary = await _frame_measurement(frames)
		detail["texture_count"] = count
		detail["texture_upload_ms"] = upload_ms
		world.queue_free()
		await process_frame
		return detail
	if selected == "canvas_overdraw":
		var world := Control.new()
		root.add_child(world)
		var count := 200 * scale
		for i in range(count):
			var layer := ColorRect.new()
			layer.color = Color(0.4, 0.7, float(i & 63) / 63.0, 0.08)
			layer.position = Vector2(float(i % 15) * 3.0, float(i % 13) * 3.0)
			layer.size = Vector2(512, 512)
			world.add_child(layer)
		var detail: Dictionary = await _frame_measurement(frames)
		detail["overdraw_rects"] = count
		world.queue_free()
		await process_frame
		return detail
	if selected == "multimesh_3d":
		var world := Node3D.new()
		root.add_child(world)
		_camera(world)
		var count := 2000 * scale
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = BoxMesh.new()
		multi.instance_count = count
		var setup := Time.get_ticks_usec()
		for i in range(count):
			var position := Vector3(float(i % 100) - 50.0, float((i / 100) % 10) * 2.0, float(i / 1000) - 5.0)
			multi.set_instance_transform(i, Transform3D(Basis(), position))
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multi
		world.add_child(instance)
		var setup_ms := float(Time.get_ticks_usec() - setup) / 1000.0
		var detail: Dictionary = await _frame_measurement(frames)
		detail["instance_count"] = count
		detail["transform_setup_ms"] = setup_ms
		world.queue_free()
		await process_frame
		return detail
	if selected == "shadow_lights":
		var world := Node3D.new()
		root.add_child(world)
		_camera(world)
		var mesh := BoxMesh.new()
		for i in range(80 * scale):
			var block := MeshInstance3D.new()
			block.mesh = mesh
			block.position = Vector3(float(i % 20) * 2.0 - 20.0, 0.0, float(i / 20) * 2.0 - 20.0)
			world.add_child(block)
		var count := 4 * scale
		for i in range(count):
			var light := OmniLight3D.new()
			light.shadow_enabled = true
			light.position = Vector3(float(i % 8) * 5.0 - 15.0, 7.0, float(i / 8) * 5.0)
			light.omni_range = 18.0
			world.add_child(light)
		var detail: Dictionary = await _frame_measurement(frames)
		detail["shadow_lights"] = count
		detail["meshes"] = 80 * scale
		world.queue_free()
		await process_frame
		return detail
	if selected == "cpu_particles":
		var world := Node2D.new()
		root.add_child(world)
		var count := 40 * scale
		for i in range(count):
			var particles := CPUParticles2D.new()
			particles.amount = 128
			particles.lifetime = 1.5
			particles.emitting = true
			particles.position = Vector2(float(i % 40) * 18.0, float(i / 40) * 18.0)
			world.add_child(particles)
		var detail: Dictionary = await _frame_measurement(frames)
		detail["emitters"] = count
		detail["particle_capacity"] = count * 128
		world.queue_free()
		await process_frame
		return detail
	if selected == "shader_variants":
		var world := Control.new()
		root.add_child(world)
		var count := 32 * scale
		var compile_start := Time.get_ticks_usec()
		for i in range(count):
			var shader := Shader.new()
			var red := float(i % 251) / 251.0
			shader.code = "shader_type canvas_item; void fragment() { COLOR = vec4(%f, 0.4, 0.8, 1.0); }" % red
			var material := ShaderMaterial.new()
			material.shader = shader
			var box := ColorRect.new()
			box.material = material
			box.position = Vector2(float(i % 16) * 36.0, float(i / 16) * 36.0)
			box.size = Vector2(32, 32)
			world.add_child(box)
		var setup_ms := float(Time.get_ticks_usec() - compile_start) / 1000.0
		var detail: Dictionary = await _frame_measurement(frames)
		detail["shader_variants"] = count
		detail["setup_ms"] = setup_ms
		world.queue_free()
		await process_frame
		return detail
	return {"error": "Unhandled GPU scenario"}
