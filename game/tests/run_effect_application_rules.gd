extends SceneTree
## godot --headless --path game --script res://tests/run_effect_application_rules.gd
const TestCase = preload("res://tests/test_case.gd")
const Suite = preload("res://tests/test_effect_application_rules.gd")

func _initialize() -> void:
	var t := TestCase.new()
	Suite.new().run(t)
	for issue in t.failures:
		printerr("FAIL " + issue)
	print("EFFECT APPLICATION RULES TOTAL: %d checks, %d failures" % [t.checks, t.failures.size()])
	quit(1 if not t.failures.is_empty() else 0)
