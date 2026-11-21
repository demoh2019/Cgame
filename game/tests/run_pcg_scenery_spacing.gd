extends SceneTree
## godot --headless --path game --script res://tests/run_pcg_scenery_spacing.gd
const TestCase = preload("res://tests/test_case.gd")
const Suite = preload("res://tests/test_pcg_scenery_spacing.gd")
const SurfaceSuite = preload("res://tests/test_pcg_surface_slope.gd")
const AlignSuite = preload("res://tests/test_pcg_surface_alignment.gd")
const RoadSuite = preload("res://tests/test_pcg_road_corridors.gd")

func _initialize() -> void:
	var t := TestCase.new()
	Suite.new().run(t)
	SurfaceSuite.new().run(t)
	AlignSuite.new().run(t)
	RoadSuite.new().run(t)
	for issue in t.failures:
		printerr("FAIL " + issue)
	print("PCG SCENERY TOTAL: %d checks, %d failures" % [t.checks, t.failures.size()])
	quit(1 if not t.failures.is_empty() else 0)
