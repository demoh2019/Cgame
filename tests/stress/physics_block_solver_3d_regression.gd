# Regression for the opt-in 3D two-contact block LCP solver.
# Run: godot --headless --path tests/stress --script res://physics_block_solver_3d_regression.gd
extends SceneTree


const BlockStress = preload("res://physics_block_solver_3d_stress.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var sequential: Dictionary = await BlockStress.new().run(self, 1, 240, false)
	var coupled: Dictionary = await BlockStress.new().run(self, 1, 240, true)
	var failures: int = 0
	for result in [sequential, coupled]:
		if int(result["failures"]) != 0:
			printerr("FAIL: non-finite state or runaway 3D box: %s" % result)
			failures += 1
		if int(result["peak_collision_pairs"]) < 12:
			printerr("FAIL: insufficient stacked-box contact pairs: %s" % result)
			failures += 1
		if int(result["settled_base_bodies"]) < 8:
			printerr("FAIL: too few base boxes settled on the floor: %s" % result)
			failures += 1

	print("Sequential 3D contacts: %s" % sequential)
	print("Coupled 3D contacts: %s" % coupled)
	if failures > 0:
		printerr("3D block solver regression failed: %d error(s)" % failures)
		quit(1)
	else:
		print("3D block solver regression passed.")
		quit(0)
