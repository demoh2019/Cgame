extends SceneTree
## Integration tests run with a headless Godot editor build:
## godot --headless --path misc/open_world_toolkit --script res://tests/run_tests.gd

const Heightmap = preload("res://addons/open_world_toolkit/terrain_data.gd")
const Terrain = preload("res://addons/open_world_toolkit/terrain_heightfield_3d.gd")
const Foliage = preload("res://addons/open_world_toolkit/foliage_scatter_3d.gd")
const WorldCell = preload("res://addons/open_world_toolkit/world_cell.gd")
const WorldPartition = preload("res://addons/open_world_toolkit/world_partition_3d.gd")

var assertions: int = 0
var failures: int = 0
var completed_cases: int = 0


func _initialize() -> void:
	call_deferred("_run_all")


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)


func _approx(value: float, expected: float, label: String, tolerance: float = 0.0001) -> void:
	_check(absf(value - expected) < tolerance, label + ": got " + str(value) + ", expected " + str(expected))


func _case(name: String) -> void:
	completed_cases += 1
	print("RUN: ", name)


func _make_map(columns: int = 5, rows: int = 5) -> OWHeightmap:
	var data := Heightmap.new() as OWHeightmap
	data.reset(columns, rows, 1.0)
	return data


func _total_height(data: OWHeightmap) -> float:
	var total := 0.0
	for value in data.heights:
		total += value
	return total


func _run_all() -> void:
	_test_dimensions()
	_test_reset_limits()
	_test_storage_length_recovery()
	_test_set_height_bounds()
	_test_sample_interpolation()
	_test_sample_clamping()
	_test_normal_flat()
	_test_normal_slope()
	_test_raise_falloff()
	_test_invalid_brush()
	_test_raise_lower_roundtrip()
	_test_smooth_spike()
	_test_flatten()
	_test_mask_paint_clamp()
	_test_mask_erase()
	_test_erode_peak()
	_test_erode_mass_conservation()
	_test_erode_noop()
	_test_deterministic_noise()
	_test_noise_seed_change()
	_test_zero_noise_amplitude()
	_test_snapshots_and_validation()
	_test_mesh_dimensions()
	_test_mesh_heights_and_normals()
	_test_mesh_blend_channel()
	_test_mesh_changes_with_resource()
	_test_ray_hit()
	_test_ray_miss()
	_test_foliage_requires_mesh()
	_test_foliage_determinism()
	_test_foliage_limits()
	_test_foliage_elevation_filter()
	_test_cell_coordinates()
	_test_cell_neighbors()
	_test_world_cell_resource()
	print("Open World Toolkit: ", completed_cases, " cases / ", assertions, " assertions / ", failures, " failures")
	quit(1 if failures > 0 else 0)


func _test_dimensions() -> void:
	_case("dimensions and initial storage")
	var data := _make_map(3, 4)
	_check(data.heights.size() == 12, "height sample count")
	_check(data.blend.size() == 12, "blend sample count")
	_approx(data.get_width(), 2.0, "width")
	_approx(data.get_depth(), 3.0, "depth")
	_check(data.contains(0.0, 0.0), "contains origin")
	_check(data.contains(2.0, 3.0), "contains far edge")
	_check(not data.contains(2.1, 3.0), "outside X")
	_check(not data.contains(2.0, -0.1), "outside negative Z")


func _test_reset_limits() -> void:
	_case("reset clamps grid to valid dimensions")
	var data := _make_map()
	data.reset(0, -4, -2.0)
	_check(data.columns == 2 and data.rows == 2, "minimum grid dimensions")
	_approx(data.cell_size, 0.01, "positive spacing")
	_check(data.heights.size() == 4, "minimum sample count")


func _test_storage_length_recovery() -> void:
	_case("corrupt storage lengths are repaired")
	var data := _make_map(3, 3)
	data.heights = PackedFloat32Array([5.0, 3.0])
	data.blend = PackedFloat32Array([0.7])
	data.ensure_storage()
	_check(data.heights.size() == 9, "height count repaired")
	_check(data.blend.size() == 9, "blend count repaired")
	_approx(data.heights[0], 5.0, "original height retained")
	_approx(data.blend[0], 0.7, "original blend retained")


func _test_set_height_bounds() -> void:
	_case("set_height validates indices and invalid numbers")
	var data := _make_map(3, 3)
	_check(data.set_height(1, 2, 9.0), "set valid")
	_approx(data.get_height(1, 2), 9.0, "get stored")
	_check(not data.set_height(-1, 0, 1.0), "reject negative x")
	_check(not data.set_height(3, 0, 1.0), "reject x overflow")
	_check(not data.set_height(0, 3, 1.0), "reject z overflow")
	_check(not data.set_height(0, 0, INF), "reject infinite values")
	_check(not data.set_height(1, 2, 9.0), "no changes on equal values")


func _test_sample_interpolation() -> void:
	_case("height bilinear sampling")
	var data := _make_map(2, 2)
	data.set_height(0, 0, 0.0)
	data.set_height(1, 0, 2.0)
	data.set_height(0, 1, 4.0)
	data.set_height(1, 1, 6.0)
	_approx(data.sample_height(0.5, 0.5), 3.0, "cell center")
	_approx(data.sample_height(0.5, 0.0), 1.0, "top midpoint")
	_approx(data.sample_height(0.0, 0.5), 2.0, "left midpoint")


func _test_sample_clamping() -> void:
	_case("sampling beyond bounds clamps to nearest edge")
	var data := _make_map(2, 2)
	data.set_height(0, 0, 7.0)
	data.set_height(1, 1, 9.0)
	_approx(data.sample_height(-100.0, -100.0), 7.0, "minimum corner")
	_approx(data.sample_height(100.0, 100.0), 9.0, "maximum corner")


func _test_normal_flat() -> void:
	_case("flat normal points up")
	var data := _make_map()
	_check(data.sample_normal(2.0, 2.0).is_equal_approx(Vector3.UP), "up-facing flat plane")


func _test_normal_slope() -> void:
	_case("surface normal reacts to slope")
	var data := _make_map(3, 3)
	for z in 3:
		data.set_height(2, z, 4.0)
	var n := data.sample_normal(1.0, 1.0)
	_check(n.x < -0.1, "slope has negative x normal")
	_check(n.y > 0.0, "slope remains upward")
	_approx(n.length(), 1.0, "unit normal")


func _test_raise_falloff() -> void:
	_case("raise sculpts center more than edges")
	var data := _make_map(9, 9)
	_check(data.sculpt(4.0, 4.0, 3.0, 8.0), "sculpt returns modified")
	_approx(data.get_height(4, 4), 8.0, "brush center")
	_check(data.get_height(4, 4) > data.get_height(3, 4), "radial falloff")
	_approx(data.get_height(0, 0), 0.0, "outside radius unchanged")


func _test_invalid_brush() -> void:
	_case("zero and invalid brush radii do nothing")
	var data := _make_map()
	_check(not data.sculpt(2.0, 2.0, 0.0, 2.0), "zero radius")
	_check(not data.sculpt(2.0, 2.0, 2.0, 0.0), "zero strength")
	_check(not data.paint(2.0, 2.0, -1.0, 1.0), "negative paint radius")
	_check(not data.paint(500.0, 500.0, 2.0, 1.0), "paint outside bounds")
	_approx(_total_height(data), 0.0, "invalid brush does not alter state")


func _test_raise_lower_roundtrip() -> void:
	_case("matching raise and lower strokes cancel")
	var data := _make_map(7, 7)
	data.sculpt(3.0, 3.0, 2.5, 5.0)
	data.sculpt(3.0, 3.0, 2.5, 5.0, OWHeightmap.SculptMode.LOWER)
	_approx(_total_height(data), 0.0, "net zero height")


func _test_smooth_spike() -> void:
	_case("smoothing reduces a height spike")
	var data := _make_map()
	data.set_height(2, 2, 12.0)
	data.sculpt(2.0, 2.0, 1.5, 1.0, OWHeightmap.SculptMode.SMOOTH)
	_check(data.get_height(2, 2) < 12.0, "center smoothed")
	_check(data.get_height(2, 2) > 0.0, "not entirely flattened")


func _test_flatten() -> void:
	_case("flatten moves sampled height toward target")
	var data := _make_map()
	data.set_height(2, 2, 10.0)
	data.sculpt(2.0, 2.0, 1.5, 1.0, OWHeightmap.SculptMode.FLATTEN, 3.0)
	_approx(data.get_height(2, 2), 3.0, "flatten target")


func _test_mask_paint_clamp() -> void:
	_case("paint saturates vertex blend mask")
	var data := _make_map()
	data.paint(2.0, 2.0, 1.5, 5.0, 1)
	_approx(data.get_blend(2, 2), 1.0, "clamp to layer 2")
	_approx(data.get_blend(0, 0), 0.0, "unpainted vertex remains layer 1")


func _test_mask_erase() -> void:
	_case("mask can be erased and clamped at zero")
	var data := _make_map()
	data.paint(2.0, 2.0, 1.5, 1.0, 1)
	data.paint(2.0, 2.0, 1.5, 2.0, 0)
	_approx(data.get_blend(2, 2), 0.0, "erase saturates zero")
	_check(not data.paint(2.0, 2.0, 1.5, 1.0, 0), "no change after fully erased")


func _test_erode_peak() -> void:
	_case("thermal erosion moves height downhill")
	var data := _make_map()
	data.set_height(2, 2, 10.0)
	_check(data.erode(3, 0.1, 0.2), "erodes steep peak")
	_check(data.get_height(2, 2) < 10.0, "peak lowered")
	_check(data.get_height(1, 2) > 0.0 or data.get_height(2, 1) > 0.0, "neighbors acquire material")


func _test_erode_mass_conservation() -> void:
	_case("thermal erosion conserves approximate total height")
	var data := _make_map(10, 10)
	data.generate_noise(123)
	var before := _total_height(data)
	data.erode(12, 0.05, 0.3)
	_approx(_total_height(data), before, "conserves material", 0.005)


func _test_erode_noop() -> void:
	_case("erosion no-ops on flat terrain and zero iterations")
	var data := _make_map()
	_check(not data.erode(8), "flat terrain does not erode")
	data.set_height(2, 2, 10.0)
	_check(not data.erode(0), "zero iterations")
	_check(not data.erode(-1), "negative iterations")
	_approx(data.get_height(2, 2), 10.0, "height stays unchanged")


func _test_deterministic_noise() -> void:
	_case("noise generation is deterministic for seed")
	var left := _make_map()
	var right := _make_map()
	left.generate_noise(17, 0.07, 5.0)
	right.generate_noise(17, 0.07, 5.0)
	_check(left.heights == right.heights, "same seed and params")


func _test_noise_seed_change() -> void:
	_case("changing noise seed changes terrain")
	var left := _make_map()
	var right := _make_map()
	left.generate_noise(17, 0.07, 5.0)
	right.generate_noise(18, 0.07, 5.0)
	_check(left.heights != right.heights, "distinct seeds")


func _test_zero_noise_amplitude() -> void:
	_case("zero amplitude creates flat terrain")
	var data := _make_map()
	data.set_height(1, 1, 7.0)
	data.generate_noise(17, 0.07, 0.0)
	_approx(_total_height(data), 0.0, "zero amplitude")


func _test_snapshots_and_validation() -> void:
	_case("snapshot restores edits and rejects wrong-sized arrays")
	var data := _make_map()
	var saved_h := data.heights.duplicate()
	var saved_b := data.blend.duplicate()
	data.set_height(2, 2, 10.0)
	data.paint(2.0, 2.0, 1.0, 1.0)
	_check(not data.set_snapshots(PackedFloat32Array(), saved_b), "reject wrong height length")
	_check(data.set_snapshots(saved_h, saved_b), "accept valid snapshot")
	_approx(data.get_height(2, 2), 0.0, "height restored")
	_approx(data.get_blend(2, 2), 0.0, "paint restored")


func _test_mesh_dimensions() -> void:
	_case("mesh has expected vertex and index counts")
	var terrain := Terrain.new() as OWTerrain3D
	terrain.heightmap = _make_map(3, 4)
	terrain.rebuild_mesh()
	_check(terrain.mesh != null, "mesh created")
	_check(terrain.mesh.get_surface_count() == 1, "one mesh surface")
	var arrays := terrain.mesh.surface_get_arrays(0)
	_check(arrays[Mesh.ARRAY_VERTEX].size() == 12, "grid vertex count")
	_check(arrays[Mesh.ARRAY_INDEX].size() == 36, "triangle indices")
	terrain.free()


func _test_mesh_heights_and_normals() -> void:
	_case("mesh geometry reflects heightfield with upward winding")
	var terrain := Terrain.new() as OWTerrain3D
	terrain.heightmap = _make_map(3, 3)
	terrain.heightmap.set_height(1, 1, 5.0)
	terrain.rebuild_mesh()
	var arrays := terrain.mesh.surface_get_arrays(0)
	_approx(arrays[Mesh.ARRAY_VERTEX][4].y, 5.0, "center mesh height")
	_check(arrays[Mesh.ARRAY_NORMAL][0].y > 0.0, "up-facing normals")
	_check(arrays[Mesh.ARRAY_INDEX][1] == 3, "first triangle winding")
	terrain.free()


func _test_mesh_blend_channel() -> void:
	_case("splat mask enters mesh vertex color channel")
	var terrain := Terrain.new() as OWTerrain3D
	terrain.heightmap = _make_map(3, 3)
	terrain.heightmap.paint(1.0, 1.0, 0.75, 1.0)
	terrain.rebuild_mesh()
	var arrays := terrain.mesh.surface_get_arrays(0)
	_approx(arrays[Mesh.ARRAY_COLOR][4].r, 1.0, "paint exported to vertex attribute")
	terrain.free()


func _test_mesh_changes_with_resource() -> void:
	_case("terrain reacts to Resource.changed")
	var terrain := Terrain.new() as OWTerrain3D
	terrain.heightmap = _make_map(3, 3)
	root.add_child(terrain)
	terrain.heightmap.set_height(1, 1, 3.0)
	var arrays := terrain.mesh.surface_get_arrays(0)
	_approx(arrays[Mesh.ARRAY_VERTEX][4].y, 3.0, "rebuild by change signal")
	terrain.free()


func _test_ray_hit() -> void:
	_case("ray picking hits a flat heightfield")
	var terrain := Terrain.new() as OWTerrain3D
	terrain.heightmap = _make_map(5, 5)
	var hit: Variant = terrain.intersect_world_ray(Vector3(2, 10, 2), Vector3.DOWN, 20.0)
	_check(hit != null, "ray intersects heightfield")
	if hit != null:
		_approx(hit.y, 0.0, "ray intersection on terrain", 0.02)
	terrain.free()


func _test_ray_miss() -> void:
	_case("ray picking rejects positions outside grid")
	var terrain := Terrain.new() as OWTerrain3D
	terrain.heightmap = _make_map(5, 5)
	_check(terrain.intersect_world_ray(Vector3(20, 10, 20), Vector3.DOWN) == null, "off-grid miss")
	_check(terrain.intersect_world_ray(Vector3(2, 10, 2), Vector3.UP) == null, "upward miss")
	terrain.free()


func _test_foliage_requires_mesh() -> void:
	_case("foliage without a mesh returns zero")
	var node := Foliage.new() as OWFoliageScatter3D
	_check(node.scatter() == 0, "unconfigured foliage")
	node.free()


func _make_foliage() -> OWFoliageScatter3D:
	var terrain := Terrain.new() as OWTerrain3D
	terrain.heightmap = _make_map(8, 8)
	var foliage := Foliage.new() as OWFoliageScatter3D
	foliage.terrain = terrain
	foliage.foliage_mesh = BoxMesh.new()
	foliage.density = 0.12
	foliage.seed = 42
	foliage.max_instances = 20
	return foliage


func _test_foliage_determinism() -> void:
	_case("foliage scatter is deterministic")
	var foliage := _make_foliage()
	var first := foliage.scatter()
	var sample := foliage.multimesh.get_instance_transform(0) if first > 0 else Transform3D.IDENTITY
	var second := foliage.scatter()
	_check(first == second, "same instance count")
	_check(first > 0, "produced instances")
	if first > 0:
		_check(sample.is_equal_approx(foliage.multimesh.get_instance_transform(0)), "same positions and scale")
	foliage.terrain.free()
	foliage.free()


func _test_foliage_limits() -> void:
	_case("foliage respects max instances")
	var foliage := _make_foliage()
	foliage.max_instances = 2
	_check(foliage.scatter() == 2, "caps instances")
	_check(foliage.multimesh.instance_count == 2, "GPU count matches")
	foliage.terrain.free()
	foliage.free()


func _test_foliage_elevation_filter() -> void:
	_case("elevation filter can reject all foliage")
	var foliage := _make_foliage()
	foliage.min_elevation = 10.0
	_check(foliage.scatter() == 0, "rejects flat ground below minimum")
	foliage.terrain.free()
	foliage.free()


func _test_cell_coordinates() -> void:
	_case("world partition floors positive and negative coordinates")
	var world := WorldPartition.new() as OWWorldPartition3D
	world.cell_size = 20.0
	_check(world.world_to_cell(Vector3(0, 0, 0)) == Vector2i.ZERO, "origin")
	_check(world.world_to_cell(Vector3(39, 0, 20)) == Vector2i(1, 1), "positive cell")
	_check(world.world_to_cell(Vector3(-1, 0, -1)) == Vector2i(-1, -1), "negative floor")
	_check(world.world_to_cell(Vector3(-20, 0, -20)) == Vector2i(-1, -1), "negative boundary")
	world.free()


func _test_cell_neighbors() -> void:
	_case("world partition square neighborhood")
	var world := WorldPartition.new() as OWWorldPartition3D
	var loaded := world.wanted_cells(Vector2i(2, -3), 1)
	_check(loaded.size() == 9, "3x3 neighborhood")
	_check(loaded.has(Vector2i(2, -3)), "includes center")
	_check(loaded.has(Vector2i(1, -4)), "includes corner")
	_check(not loaded.has(Vector2i(4, -3)), "excludes outside neighbor")
	_check(world.wanted_cells(Vector2i.ZERO, -1).size() == 1, "negative radius clamped")
	world.free()


func _test_world_cell_resource() -> void:
	_case("cell resources store scene and coordinates")
	var resource := WorldCell.new() as OWWorldCell
	resource.coordinate = Vector2i(-4, 9)
	resource.scene_path = "res://demo/world_demo.tscn"
	_check(resource.coordinate == Vector2i(-4, 9), "cell coordinate retained")
	_check(resource.scene_path.ends_with(".tscn"), "resource path retained")