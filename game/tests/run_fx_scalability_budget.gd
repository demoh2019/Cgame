extends SceneTree
## Fast native-and-stock Godot VFX regression for the significance workflow.
const TestCase = preload("res://tests/test_case.gd")
const Suite = preload("res://tests/test_fx_scalability_budget.gd")


func _initialize() -> void:
	var t = TestCase.new()
	Suite.new().run(t)
	for failure in t.failures:
		printerr("FAIL ", failure)
	print("FX SCALABILITY TOTAL: %d checks, %d failures" % [t.checks, t.failures.size()])
	quit(0 if t.failures.is_empty() else 1)
