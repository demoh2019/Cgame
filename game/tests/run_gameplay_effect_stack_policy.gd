extends SceneTree
## godot --headless --path game --script res://tests/run_gameplay_effect_stack_policy.gd
const TestCase = preload("res://tests/test_case.gd")
const Suite = preload("res://tests/test_gameplay_effect_stack_policy.gd")

func _initialize() -> void:
	var t := TestCase.new()
	Suite.new().run(t)
	for issue in t.failures:
		printerr("FAIL " + issue)
	print("GAMEPLAY STACK POLICY TOTAL: %d checks, %d failures" % [t.checks, t.failures.size()])
	quit(1 if not t.failures.is_empty() else 0)
