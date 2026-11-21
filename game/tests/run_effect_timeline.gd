extends SceneTree
## godot --headless --path game --script res://tests/run_effect_timeline.gd
const TestCase = preload("res://tests/test_case.gd")
const Suite = preload("res://tests/test_runtime_effect_timeline.gd")

func _initialize() -> void:
	var t := TestCase.new()
	Suite.new().run(t)
	for failure in t.failures:
		printerr("FAIL " + failure)
	print("EFFECT TIMELINE TOTAL: %d checks, %d failures" % [t.checks, t.failures.size()])
	quit(1 if not t.failures.is_empty() else 0)
