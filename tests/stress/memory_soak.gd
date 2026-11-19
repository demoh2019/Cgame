extends SceneTree
## Long-lived memory stress: repeated allocation/release in ONE Godot process.
## Run via memory_soak.py. MEMORY_STATIC is NOT the process RSS.

const PREFIX := "STRESS_RESULT:"
const SCENARIOS := ["nodes", "packed"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scenario := "nodes"
	var batch := 300
	var cycles := 120
	var seed := 12345
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scenario="):
			scenario = argument.trim_prefix("--scenario=")
		elif argument.begins_with("--scale="):
			batch = int(argument.trim_prefix("--scale="))
		elif argument.begins_with("--frames="):
			cycles = int(argument.trim_prefix("--frames="))
		elif argument.begins_with("--seed="):
			seed = int(argument.trim_prefix("--seed="))
	if not SCENARIOS.has(scenario) or batch < 1 or batch > 1000 or cycles < 4 or cycles > 100000:
		printerr("Invalid memory_soak arguments")
		quit(2)
		return

	var samples: Array[int] = []
	var started := Time.get_ticks_usec()
	for cycle in range(cycles):
		if scenario == "nodes":
			var parent := Node.new()
			root.add_child(parent)
			for index in range(batch):
				var node := Node2D.new()
				node.position = Vector2(float(index & 63), float(cycle & 63))
				parent.add_child(node)
			parent.free()
		else:
			var allocations: Array[PackedByteArray] = []
			for index in range(batch):
				var block := PackedByteArray()
				block.resize(8192)
				block[0] = (index + cycle) & 255
				block[block.size() - 1] = seed & 255
				allocations.append(block)
			allocations.clear()
		await process_frame
		samples.append(int(Performance.get_monitor(Performance.MEMORY_STATIC)))

	var result := {
		"case": "memory_soak",
		"scale": batch,
		"frames": cycles,
		"seed": seed,
		"duration_ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"detail": {
			"scenario": scenario,
			"cycles": cycles,
			"batch": batch,
			"engine_static_memory_bytes": samples,
		},
	}
	print(PREFIX + JSON.stringify(result))
	quit(0)
