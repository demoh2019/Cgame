extends SceneTree
## Bounded multi-actor EQS and authoritative raid spawn regression.
## godot --headless --path game --script res://tests/run_raid_eqs.gd

const TestCase = preload("res://tests/test_case.gd")
const SUITES := [
	"res://tests/test_raid_multi_threat_query.gd",
	"res://tests/test_raid_reinforcements.gd",
]


func _initialize() -> void:
	var total_checks := 0
	var failures: Array[String] = []
	for path in SUITES:
		var script := load(path) as GDScript
		if script == null:
			failures.append("%s: could not load regression script" % path)
			continue
		var suite = script.new()
		var t := TestCase.new()
		suite.run(t)
		total_checks += t.checks
		failures.append_array(t.failures)
		print("%s: %d checks, %d failures" % [path.get_file(), t.checks, t.failures.size()])
	for failure in failures:
		printerr("FAIL " + failure)
	print("RAID EQS TOTAL: %d checks, %d failures" % [total_checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)
