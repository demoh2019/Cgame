extends SceneTree
## Runs selected suites only (fast local iteration):
## godot --headless --path game --script res://tests/run_one.gd -- test_gear_durability [test_other ...]

const TestCase = preload("res://tests/test_case.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var total := 0
	for name in OS.get_cmdline_user_args():
		var path: String = name if name.begins_with("res://") else "res://tests/%s.gd" % name.trim_suffix(".gd")
		var script: GDScript = load(path)
		# A suite with a parse error must not abort the whole run: record it and continue.
		if script == null or not script.can_instantiate():
			failures.append("%s: could not load" % path)
			continue
		var t := TestCase.new()
		script.new().run(t)
		total += t.checks
		failures.append_array(t.failures)
		print("%-34s %4d checks  %3d failed" % [path.get_file(), t.checks, t.failures.size()])
	for failure in failures:
		printerr("FAIL " + failure)
	print("TOTAL %d checks, %d failures" % [total, failures.size()])
	quit(1 if failures.size() > 0 else 0)
