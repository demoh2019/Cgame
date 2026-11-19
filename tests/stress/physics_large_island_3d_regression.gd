# Runtime regression: serial, graph-colored and high-priority 3D islands.
# Run: godot --headless --path tests/stress --script res://physics_large_island_3d_regression.gd
extends SceneTree

const LargeIsland3DStress := preload("res://physics_large_island_3d.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures := 0
	# Compare equal geometry in serial/parallel modes. The last case has
	# two large islands and must use ordinary island-level workers.
	for parameters in [[false, false, 0, 16], [true, false, 0, 16], [true, true, 0, 16],
			[false, false, 20, 16], [true, false, 20, 16], [true, true, 20, 16],
			[true, false, 1, 320]]:
		var parallel: bool = parameters[0]
		var priority_fallback: bool = parameters[1]
		var extra_islands: int = parameters[2]
		var extra_island_size: int = parameters[3]
		var result: Dictionary = await LargeIsland3DStress.new().run(
				self, 1, 24, parallel, priority_fallback, extra_islands, extra_island_size)
		if result.has("error"):
			printerr("FAIL: 3D island: parallel=%s, fallback=%s, error=%s" %
					[parallel, priority_fallback, result["error"]])
			failures += 1
			continue
		if (int(result["joints"]) < 256 or float(result["max_joint_spacing"]) > 11.0
				or int(result["bodies"]) != 320 + extra_islands * extra_island_size):
			printerr("FAIL: incorrect connected-island test geometry or joint drift")
			failures += 1
		print("3D island: parallel=%s, priority_fallback=%s, extra=%d, joints=%d, peak=%.3f ms" %
				[parallel, priority_fallback, extra_islands, result["joints"], result["peak_physics_ms"]])

	if failures != 0:
		printerr("3D large island regression failed (%d errors)" % failures)
		quit(1)
	else:
		print("3D large island regression passed.")
		quit(0)


func _frame_statistics(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {"p50": 0.0, "p95": 0.0, "max": 0.0}
	var ordered := samples.duplicate()
	ordered.sort()
	var count := ordered.size()
	return {
		"p50": ordered[int(float(count - 1) * 0.5)],
		"p95": ordered[clampi(ceili(float(count) * 0.95) - 1, 0, count - 1)],
		"max": ordered[count - 1],
	}
