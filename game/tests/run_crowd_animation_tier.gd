extends SceneTree
## godot --headless --path game --script res://tests/run_crowd_animation_tier.gd
const TestCase = preload("res://tests/test_case.gd")
const Suite = preload("res://tests/test_crowd_animation_tier_planner.gd")


func _initialize() -> void:
	var t := TestCase.new()
	Suite.new().run(t)
	for error in t.failures:
		printerr("FAIL " + error)
	print("CROWD LOD TOTAL: %d checks, %d failures" % [t.checks, t.failures.size()])
	quit(1 if not t.failures.is_empty() else 0)
