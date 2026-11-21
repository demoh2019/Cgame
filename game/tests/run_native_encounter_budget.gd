extends SceneTree
## Focused authoritative incident pressure and native/stock fallback parity.
const TestCase = preload("res://tests/test_case.gd")
const Suite = preload("res://tests/test_world_encounter_director.gd")


func _initialize() -> void:
	var t := TestCase.new()
	Suite.new().run(t)
	for failure in t.failures:
		printerr("FAIL " + failure)
	print("ENCOUNTER BUDGET TOTAL: %d checks, %d failures" % [
		t.checks, t.failures.size()])
	quit(1 if not t.failures.is_empty() else 0)
