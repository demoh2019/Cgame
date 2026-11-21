extends SceneTree
## godot --headless --path game --script res://tests/run_pack_spatial.gd
const TestCase = preload("res://tests/test_case.gd")
const PackSuite = preload("res://tests/test_zombie_pack.gd")


func _initialize() -> void:
	var t := TestCase.new()
	PackSuite.new().run(t)
	for failure in t.failures:
		printerr("FAIL " + failure)
	print("PACK SPATIAL TOTAL: %d checks, %d failures" % [t.checks, t.failures.size()])
	quit(0 if t.failures.is_empty() else 1)
