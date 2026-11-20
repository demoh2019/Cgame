extends SceneTree
const TestCase = preload("res://tests/test_case.gd")
func _initialize() -> void:
	for name in OS.get_environment("SUITES").split(","):
		var suite = (load("res://tests/%s.gd" % name) as GDScript).new()
		var t := TestCase.new()
		suite.run(t)
		print("%s %d checks %d failed" % [name, t.checks, t.failures.size()])
		for f in t.failures: print("  FAIL ", f)
	quit()
