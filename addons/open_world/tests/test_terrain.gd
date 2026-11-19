extends SceneTree
## Engine-level headless test runner. Exits nonzero on regression.

const TERRAIN: Script = preload("res://addons/open_world/terrain_world.gd")

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


func _approx(a: float, b: float, tolerance: float = 0.0001) -> bool:
	return absf(a - b) <= tolerance


func _sum_heights(heights: PackedFloat32Array) -> float:
	var total := 0.0
	for height in heights:
		total += height
	return total


func _run_tests() -> void:
	var terrain: Variant = TERRAIN.new()
	terrain.resolution = 8
	terrain.cell_size = 1.0
	get_root().add_child(terrain)
	terrain.call("rebuild")

	var heights: PackedFloat32Array = terrain.call("get_height_copy")
	var colors: PackedColorArray = terrain.call("get_paint_copy")
	_check(heights.size() == 81, "9x9 vertex heights")
	_check(colors.size() == 81, "9x9 paint weights")
	var terrain_mesh := terrain.get_node("__OpenWorldTerrainMesh") as MeshInstance3D
	_check(terrain_mesh != null and terrain_mesh.mesh != null and terrain_mesh.mesh.get_surface_count() == 1, "one renderable terrain surface")
	_check(terrain.call("get_collision_body") != null, "terrain collision is generated")
	for color in colors:
		_check(color == Color(1.0, 0.0, 0.0, 0.0), "default paint is base layer")
	for h in heights:
		_check(_approx(h, 0.0), "default height is zero")

	# Grid is centered, so cell (4, 4) corresponds to local (0, 0).
	var point := terrain.to_global(Vector3.ZERO)
	var far_point := terrain.to_global(Vector3(100.0, 0.0, 100.0))
	_check(terrain.call("apply_brush", far_point, 2.0, 1.0, 0, 0) == 0, "out-of-bounds brush is ignored")
	_check(terrain.call("apply_brush", point, 0.0, 1.0, 0, 0) == 0, "zero-radius brush is ignored")
	_check(terrain.call("apply_brush", point, 1.5, 0.0, 0, 0) == 0, "zero-strength brush is ignored")
	_check(terrain.call("apply_brush", point, 0.5, 2.0, 0, 0) == 1, "small raise brush only edits center")
	heights = terrain.call("get_height_copy")
	_check(_approx(heights[40], 2.0), "raise changes center height")
	_check(_approx(heights[39], 0.0), "raise leaves neighbor untouched")
	_check(_approx(terrain.call("sample_height", 0.0, 0.0), 2.0), "height sampling at vertex")
	_check(_approx(terrain.call("sample_height", 0.5, 0.0), 1.0), "bilinear height sampling")
	_check(_approx(terrain.call("sample_height", 100.0, 100.0), 0.0), "height sampling clamps outside bounds")

	terrain.call("apply_brush", point, 0.5, 1.0, 1, 0)
	_check(_approx(terrain.call("sample_height", 0.0, 0.0), 1.0), "lower brush")
	terrain.call("apply_brush", point, 0.5, 1.0, 2, 0)
	_check(_approx(terrain.call("sample_height", 0.0, 0.0), 0.0), "smooth brush averages neighbors")

	_check(terrain.call("apply_brush", point, 0.5, 1.0, 3, 2) == 1, "paint brush edits center")
	colors = terrain.call("get_paint_copy")
	_check(colors[40].is_equal_approx(Color(0.0, 0.0, 1.0, 0.0)), "paint assigns layer 2")
	_check(colors[39] == Color(1.0, 0.0, 0.0, 0.0), "paint does not affect outside vertices")
	terrain.call("apply_brush", point, 0.5, 1.0, 3, 3)
	colors = terrain.call("get_paint_copy")
	_check(colors[40].is_equal_approx(Color(0.0, 0.0, 0.0, 1.0)), "layer 3 uses alpha channel")

	# Restoring data simulates Undo/Redo and has to preserve both arrays.
	var saved_heights: PackedFloat32Array = terrain.call("get_height_copy")
	var saved_colors: PackedColorArray = terrain.call("get_paint_copy")
	terrain.call("apply_brush", point, 0.5, 3.0, 0, 0)
	terrain.call("apply_brush", point, 0.5, 1.0, 3, 1)
	terrain.call("restore_data", saved_heights, saved_colors)
	_check(terrain.call("get_height_copy") == saved_heights, "height undo restore")
	_check(terrain.call("get_paint_copy") == saved_colors, "paint undo restore")

	# Thermal erosion transports height without changing total material volume.
	heights.fill(0.0)
	heights[40] = 10.0
	terrain.call("restore_data", heights, saved_colors)
	var sum_before: float = _sum_heights(terrain.call("get_height_copy"))
	terrain.call("thermal_erode", 4, 0.1, 0.1)
	var after: PackedFloat32Array = terrain.call("get_height_copy")
	_check(after[40] < 10.0, "erosion lowers sharp peaks")
	_check(after[39] > 0.0, "erosion redistributes height to neighbors")
	_check(_approx(_sum_heights(after), sum_before, 0.001), "erosion conserves height mass")
	terrain.call("thermal_erode", 0, 0.1, 0.1)
	_check(terrain.call("get_height_copy") == after, "zero iterations are identity")

	# Foliage must be deterministic, independent, and batched.
	terrain.foliage_mesh = BoxMesh.new()
	terrain.call("scatter_foliage", 40, 77, 0.0)
	var points: PackedVector3Array = terrain.call("get_foliage_points_copy")
	var scales: PackedFloat32Array = terrain.call("get_foliage_scales_copy")
	_check(points.size() == 40, "requested foliage count")
	_check(scales.size() == 40, "foliage scale count")
	var foliage_renderer := terrain.get_node("__OpenWorldFoliage") as MultiMeshInstance3D
	var multimesh: MultiMesh = foliage_renderer.multimesh
	_check(multimesh != null and multimesh.instance_count == 40, "foliage is GPU-instanced")
	terrain.call("scatter_foliage", 40, 77, 0.0)
	_check(points == terrain.call("get_foliage_points_copy"), "foliage positions are reproducible")
	_check(scales == terrain.call("get_foliage_scales_copy"), "foliage scales are reproducible")
	terrain.call("scatter_foliage", 40, 78, 0.0)
	_check(points != terrain.call("get_foliage_points_copy"), "different seed changes placement")
	terrain.call("restore_foliage", points, scales)
	_check(points == terrain.call("get_foliage_points_copy"), "foliage restores by data")

	terrain.queue_free()
	if failures == 0:
		print("OPEN_WORLD_TESTS_OK")
	else:
		printerr("Open World terrain failures: %d" % failures)
	quit(1 if failures > 0 else 0)
