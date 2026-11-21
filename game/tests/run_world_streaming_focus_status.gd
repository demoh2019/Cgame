extends SceneTree
## godot --headless --path game --script res://tests/run_world_streaming_focus_status.gd
const TestCase = preload("res://tests/test_case.gd")
const Suite = preload("res://tests/test_world_streaming_focus_status.gd")


func _initialize() -> void:
	var t := TestCase.new()
	Suite.new().run(t)
	for failure in t.failures:
		printerr("FAIL " + failure)
	print("FOCUS STREAMING TOTAL: %d checks, %d failures" % [t.checks, t.failures.size()])
	quit(1 if not t.failures.is_empty() else 0)
