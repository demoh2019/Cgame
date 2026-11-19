extends SceneTree
## godot --headless --path game --script res://tests/run_all.gd
## Runs every test_*.gd that does not need a network. Each test script has a `run(t)` method.

const TestCase = preload("res://tests/test_case.gd")
const SUITES := [
	"res://tests/test_world_gen.gd",
	"res://tests/test_inventory.gd",
	"res://tests/test_crafting.gd",
	"res://tests/test_survival_combat.gd",
	"res://tests/test_movement.gd",
	"res://tests/test_encumbrance.gd",
	"res://tests/test_zombie_ai.gd",
	"res://tests/test_game_server.gd",
	"res://tests/test_secure_stash.gd",
]


func _initialize() -> void:
	var total_checks := 0
	var failures: Array[String] = []
	for path in SUITES:
		var script: GDScript = load(path)
		if script == null:
			failures.append("%s: could not load" % path)
			continue
		var suite = script.new()
		var t := TestCase.new()
		var started := Time.get_ticks_msec()
		suite.run(t)
		total_checks += t.checks
		failures.append_array(t.failures)
		print("%-34s %4d checks  %3d failed  %4d ms" % [path.get_file(), t.checks, t.failures.size(), Time.get_ticks_msec() - started])
	for failure in failures:
		printerr("FAIL " + failure)
	print("TOTAL %d checks, %d failures" % [total_checks, failures.size()])
	quit(1 if failures.size() > 0 else 0)
