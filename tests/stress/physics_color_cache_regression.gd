# Exercise persistent graph-color cache reuse and invalidation across joint rewiring.
# Run: godot --headless --path tests/stress --script res://physics_color_cache_regression.gd
extends SceneTree


const LargeIslandStress = preload("res://physics_large_island_stress.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures: int = 0
	# Both runs use identical topology mutations. The second enables the
	# experimental coloring/cache path; the first is the sequential baseline.
	for parallel in [false, true]:
		var result: Dictionary = await LargeIslandStress.new().run(self, 1, 150, parallel, 1, 0, true)
		print("Persistent color cache, parallel=%s: %s" % [parallel, result])
		if not bool(result["valid"]):
			printerr("FAIL: non-finite or runaway chain after joint rebinding")
			failures += 1
		if int(result["topology_changes"]) != 2:
			printerr("FAIL: did not rebind and restore the joint")
			failures += 1
		if int(result["joints"]) != 383 or int(result["peak_solver_islands"]) < 1:
			printerr("FAIL: expected 383 constraints in one active chain")
			failures += 1
		if float(result["max_joint_gap"]) > 9.2:
			printerr("FAIL: joints separated after topology changes")
			failures += 1

	if failures > 0:
		printerr("Persistent 2D color cache regression failed: %d" % failures)
		quit(1)
	else:
		print("Persistent 2D color cache regression passed.")
		quit(0)
