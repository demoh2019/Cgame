# Regression: color-parallel and sequential solvers on the same connected 2D chain.
# Run: godot --headless --path tests/stress --script res://physics_large_island_regression.gd
extends SceneTree


const LargeIslandStress = preload("res://physics_large_island_stress.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Exercise all three scheduling paths:
	#  * one large island (graph-coloring candidate)
	#  * one large + one small island (defer the large, solve the small)
	#  * two large + one small island (parallel island-level jobs)
	var configurations: Array[Dictionary] = [
		{"label": "single", "large": 1, "small": 0, "frames": 120},
		{"label": "mixed", "large": 1, "small": 48, "frames": 90},
		{"label": "multiple", "large": 2, "small": 48, "frames": 90},
	]
	var failures: int = 0

	for config in configurations:
		var large: int = int(config["large"])
		var small: int = int(config["small"])
		var frames: int = int(config["frames"])
		var serial: Dictionary = await LargeIslandStress.new().run(self, 1, frames, false, large, small)
		var parallel: Dictionary = await LargeIslandStress.new().run(self, 1, frames, true, large, small)
		var expected_bodies: int = 384 * large + small
		var expected_islands: int = large + (1 if small > 0 else 0)
		var expected_joints: int = expected_bodies - expected_islands

		for result in [serial, parallel]:
			if not bool(result["valid"]):
				printerr("FAIL (%s): unstable constraints: %s" % [config["label"], result])
				failures += 1
			if int(result["bodies"]) != expected_bodies or int(result["joints"]) != expected_joints:
				printerr("FAIL (%s): incorrect chain construction: %s" % [config["label"], result])
				failures += 1
			if int(result["islands"]) != expected_islands:
				printerr("FAIL (%s): expected %d islands: %s" % [config["label"], expected_islands, result])
				failures += 1
			if float(result["max_joint_gap"]) > 9.2:
				printerr("FAIL (%s): excessive joint separation: %s" % [config["label"], result])
				failures += 1

		print("%s serial: %s" % [config["label"], serial])
		print("%s parallel: %s" % [config["label"], parallel])

	if failures > 0:
		printerr("Large-island regression failed: %d error(s)" % failures)
		quit(1)
	else:
		print("Large-island regression passed.")
		quit(0)
