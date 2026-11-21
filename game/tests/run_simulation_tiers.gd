extends SceneTree
## Focused native WorldStreamer simulation integration suite.

const TestCase = preload("res://tests/test_case.gd")
const TestSuite = preload("res://tests/test_world_streamer_simulation_tiers.gd")


func _initialize() -> void:
	var t = TestCase.new()
	TestSuite.new().run(t)
	for failure in t.failures:
		printerr("FAIL " + failure)
	print("SIMULATION TIERS TOTAL: %d checks, %d failures" % [t.checks, t.failures.size()])
	quit(1 if not t.failures.is_empty() else 0)
