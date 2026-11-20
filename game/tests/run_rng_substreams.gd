extends SceneTree
## Focused game seed-stream tests for stock Godot and Cgame native builds.
## godot --headless --path game --script res://tests/run_rng_substreams.gd

const TestCase = preload("res://tests/test_case.gd")
const SUITES := [
	"res://tests/test_seeded_substreams.gd",
	"res://tests/test_ambient_birds.gd",
]


func _initialize() -> void:
	var total_checks := 0
	var failures: Array[String] = []
	for path in SUITES:
		var script := load(path) as GDScript
		if script == null:
			failures.append("%s: missing or invalid test script" % path)
			continue
		var suite = script.new()
		var t := TestCase.new()
		suite.run(t)
		total_checks += t.checks
		failures.append_array(t.failures)
		print("%s: %d checks, %d failures" % [path.get_file(), t.checks, t.failures.size()])
	for fail in failures:
		printerr("FAIL " + fail)
	print("RNG SUBSTREAM TOTAL: %d checks, %d failures" % [total_checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)
