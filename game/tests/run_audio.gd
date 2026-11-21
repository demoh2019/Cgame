extends SceneTree
## Focused audio tests on Cgame native or stock Godot:
## godot --headless --path game --script res://tests/run_audio.gd

const TestCase = preload("res://tests/test_case.gd")
const SUITES := [
	"res://tests/test_audio_parity.gd",
	"res://tests/test_audio_geometry_occlusion.gd",
	"res://tests/test_audio_occlusion_envelope.gd",
	"res://tests/test_audio_occlusion_probe_planner.gd",
]


func _initialize() -> void:
	var total := 0
	var failures: Array[String] = []
	for path in SUITES:
		var script := load(path) as GDScript
		if script == null:
			failures.append("%s: missing or invalid test script" % path)
			continue
		var suite = script.new()
		var test := TestCase.new()
		suite.run(test)
		total += test.checks
		failures.append_array(test.failures)
		print("%s: %d checks, %d failed" % [
			path.get_file(), test.checks, test.failures.size()])
	for failed in failures:
		printerr("FAIL " + failed)
	print("AUDIO TOTAL: %d checks, %d failures" % [total, failures.size()])
	quit(1 if failures.size() > 0 else 0)
