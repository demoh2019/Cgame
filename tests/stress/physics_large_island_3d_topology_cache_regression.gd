# Exercise topology-invalidating joint changes while 3D color caching is hot.
# Run: godot --headless --path tests/stress --script res://physics_large_island_3d_topology_cache_regression.gd
extends SceneTree

const LargeIsland3DStress := preload("res://physics_large_island_3d.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var errors := 0
	for parallel in [false, true]:
		# 320 connected bodies exceed the colored-solver threshold; the
		# same joint is re-bound twice and a different joint priority changes.
		var result: Dictionary = await LargeIsland3DStress.new().run(
				self, 1, 52, parallel, false, 0, 16, true)
		if result.has("error"):
			printerr("FAIL: topology churn (%s): %s" % [parallel, result["error"]])
			errors += 1
			continue
		if int(result["joints"]) != 319 or not bool(result["topology_churn"]):
			printerr("FAIL: invalid 3D topology-churn scenario")
			errors += 1
		print("3D topology cache: parallel=%s, joints=%d, peak=%.3f ms" %
				[parallel, result["joints"], result["peak_physics_ms"]])

	if errors == 0:
		print("3D topology-cache regression passed.")
	else:
		printerr("3D topology-cache regression failed: %d case(s)" % errors)
	quit(1 if errors > 0 else 0)


func _frame_statistics(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {"p50": 0.0, "p95": 0.0, "max": 0.0}
	var sorted := samples.duplicate()
	sorted.sort()
	var count := sorted.size()
	return {
		"p50": sorted[int(float(count - 1) * 0.5)],
		"p95": sorted[clampi(ceili(float(count) * 0.95) - 1, 0, count - 1)],
		"max": sorted.back(),
	}
