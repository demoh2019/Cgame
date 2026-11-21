extends SceneTree
## Focused game parity check, works in stock Godot and custom Cgame editor.
## godot --headless --path game --script res://tests/run_dynamic_resolution_panic.gd
const TestCase = preload("res://tests/test_case.gd")
const Suite = preload("res://tests/test_graphics_resolution_panic.gd")


func _initialize() -> void:
	var t := TestCase.new()
	Suite.new().run(t)
	for failure in t.failures:
		printerr("FAIL " + failure)
	print("GPU PANIC TOTAL: %d checks, %d failures" % [t.checks, t.failures.size()])
	quit(1 if t.failures.size() > 0 else 0)
