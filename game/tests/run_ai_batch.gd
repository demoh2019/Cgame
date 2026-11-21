extends SceneTree
## godot --headless --path game --script res://tests/run_ai_batch.gd
## Tests native batch scheduling and authoritative server fallback.
const TestCase = preload("res://tests/test_case.gd")
const Suite = preload("res://tests/test_ai_update_scheduler.gd")


func _initialize() -> void:
	var t := TestCase.new()
	Suite.new().run(t)
	for failure in t.failures:
		printerr("FAIL " + failure)
	print("AI BATCH TOTAL: %d checks, %d failures" % [t.checks, t.failures.size()])
	quit(0 if t.failures.is_empty() else 1)
