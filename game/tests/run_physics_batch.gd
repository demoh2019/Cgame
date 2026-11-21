extends SceneTree
## Focused engine/game physics-ray and audio occlusion tests.
## godot --headless --path game --script res://tests/run_physics_batch.gd

const TestCase = preload("res://tests/test_case.gd")
const SUITES := [
	"res://tests/test_native_batch_rays.gd",
	"res://tests/test_audio_geometry_occlusion.gd",
	"res://tests/test_audio_parity.gd",
]


func _initialize() -> void:
	var total_checks := 0
	var failures: Array[String] = []
	for path in SUITES:
		var script := load(path) as GDScript
		if script == null:
			failures.append("%s: cannot load test script" % path)
			continue
		var suite = script.new()
		var t := TestCase.new()
		suite.run(t)
		total_checks += t.checks
		failures.append_array(t.failures)
		print("%s: %d checks, %d failures" % [path.get_file(), t.checks, t.failures.size()])
	for fail in failures:
		printerr("FAIL " + fail)
	print("PHYSICS BATCH TOTAL: %d checks, %d failures" % [total_checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)
