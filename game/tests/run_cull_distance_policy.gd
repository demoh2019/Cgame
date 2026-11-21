extends SceneTree
## godot --headless --path game --script res://tests/run_cull_distance_policy.gd
## Dedicated native/stock-Godot bounds-aware LOD parity suite.
const TestCase = preload("res://tests/test_case.gd")
const Suite = preload("res://tests/test_scenery_lod.gd")

func _initialize() -> void:
	var t := TestCase.new()
	Suite.new().run(t)
	for failure in t.failures:
		printerr("FAIL " + failure)
	print("CULL DISTANCE TOTAL: %d checks, %d failures" %
		[t.checks, t.failures.size()])
	quit(1 if not t.failures.is_empty() else 0)
