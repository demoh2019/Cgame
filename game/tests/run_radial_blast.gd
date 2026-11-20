extends SceneTree
## Fast, renderer-independent radial blast and physics parity regressions.
## godot --headless --path game --script res://tests/run_radial_blast.gd

const TestCase = preload("res://tests/test_case.gd")
const SUITES := [
	"res://tests/test_radial_blast_shielding.gd",
	"res://tests/test_physics_parity.gd",
]


func _initialize() -> void:
	var checks := 0
	var failures: Array[String] = []
	for path in SUITES:
		var script := load(path) as GDScript
		if script == null:
			failures.append("%s: cannot load" % path)
			continue
		var suite = script.new()
		var t := TestCase.new()
		suite.run(t)
		checks += t.checks
		failures.append_array(t.failures)
		print("%s: %d checks, %d failures" % [path.get_file(), t.checks, t.failures.size()])
	for failure in failures:
		printerr("FAIL " + failure)
	print("RADIAL BLAST TOTAL: %d checks, %d failures" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)
