extends SceneTree
## Focused native-engine terrain residency test runner; no game server required.
## Run after building the Cgame editor:
##   ./bin/godot.linuxbsd.editor.x86_64 --headless --path game --script res://tests/run_terrain_mesh_residency.gd

const TestCase = preload("res://tests/test_case.gd")
const Suite = preload("res://tests/test_terrain_mesh_residency.gd")


func _initialize() -> void:
	var t := TestCase.new()
	Suite.new().run(t)
	for failure in t.failures:
		printerr("FAIL " + failure)
	print("TERRAIN GPU RESIDENCY TOTAL: %d checks, %d failures" % [t.checks, t.failures.size()])
	quit(1 if not t.failures.is_empty() else 0)
