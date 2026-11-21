extends SceneTree
## godot --headless --path game --script res://tests/run_ambient_budget.gd
## Runs native/stock cosmetic scheduling parity without loading an online world.
const TestCase = preload("res://tests/test_case.gd")
const Suite = preload("res://tests/test_ambient_tick_budget.gd")


func _initialize() -> void:
	var t := TestCase.new()
	var suite := Suite.new()
	suite.run(t)
	for error in t.failures:
		printerr("FAIL " + error)
	print("AMBIENT FAIRNESS TOTAL: %d checks, %d failures" % [t.checks, t.failures.size()])
	quit(1 if not t.failures.is_empty() else 0)
