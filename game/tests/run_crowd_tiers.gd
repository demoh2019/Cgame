extends SceneTree
## Standalone headless native/fallback crowd LOD and combat priority regression.
## godot --headless --path game --script res://tests/run_crowd_tiers.gd

const TestCase = preload("res://tests/test_case.gd")
const SUITES := [
	"res://tests/test_crowd_animation_tier_planner.gd",
	"res://tests/test_combat_animation_priority.gd",
	"res://tests/test_anim_lod.gd",
]


func _initialize() -> void:
	var total: int = 0
	var failures: Array[String] = []
	for path in SUITES:
		var source: GDScript = load(path) as GDScript
		if source == null:
			failures.append("Cannot load %s" % path)
			continue
		var t = TestCase.new()
		source.new().run(t)
		total += t.checks
		failures.append_array(t.failures)
		print("%s: %d checks, %d failures" % [path.get_file(), t.checks, t.failures.size()])
	for error in failures:
		printerr("FAIL " + error)
	print("CROWD TIERS TOTAL: %d checks, %d failures" % [total, failures.size()])
	quit(1 if not failures.is_empty() else 0)
