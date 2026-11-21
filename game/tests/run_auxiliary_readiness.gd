extends SceneTree
## Focused native auxiliary streaming diagnostics + map integration tests.
const TestCase = preload("res://tests/test_case.gd")
const Suite = preload("res://tests/test_auxiliary_streaming_readiness.gd")


func _initialize() -> void:
	var t = TestCase.new()
	Suite.new().run(t)
	for failure in t.failures:
		printerr("FAIL " + failure)
	print("AUXILIARY READINESS TOTAL: %d checks, %d failures" % [t.checks, t.failures.size()])
	quit(1 if not t.failures.is_empty() else 0)
