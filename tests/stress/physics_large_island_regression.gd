# Regression: color-parallel and sequential solvers on the same connected 2D chain.
# Run: godot --headless --path tests/stress --script res://physics_large_island_regression.gd
extends SceneTree


const LargeIslandStress = preload("res://physics_large_island_stress.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# The work is large enough to cross the parallelization threshold.
	var serial: Dictionary = await LargeIslandStress.new().run(self, 1, 120, false)
	var parallel: Dictionary = await LargeIslandStress.new().run(self, 1, 120, true)
	var failures: int = 0

	for result in [serial, parallel]:
		if not bool(result["valid"]):
			printerr("FAIL: unstable constraints: %s" % result)
			failures += 1
		if int(result["joints"]) != 383:
			printerr("FAIL: test did not build a connected large island: %s" % result)
			failures += 1
		if float(result["max_joint_gap"]) > 9.2:
			printerr("FAIL: excessive joint separation: %s" % result)
			failures += 1

	print("Sequential large island: %s" % serial)
	print("Parallel large island: %s" % parallel)
	if failures > 0:
		printerr("Large-island regression failed: %d error(s)" % failures)
		quit(1)
	else:
		print("Large-island regression passed.")
		quit(0)
