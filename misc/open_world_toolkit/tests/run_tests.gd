extends SceneTree
## Integration tests run with a headless Godot editor build:
## godot --headless --path misc/open_world_toolkit --script res://tests/run_tests.gd

const Heightmap = preload("res://addons/open_world_toolkit/terrain_data.gd")
const Terrain = preload("res://addons/open_world_toolkit/terrain_heightfield_3d.gd")
const Foliage = preload("res://addons/open_world_toolkit/foliage_scatter_3d.gd")
const WorldCell = preload("res://addons/open_world_toolkit/world_cell.gd")
const WorldPartition = preload("res://addons/open_world_toolkit/world_partition_3d.gd")
const PCG = preload("res://addons/open_world_toolkit/pcg_graph.gd")

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
	_test_pcg_default()
	_test_pcg_empty_invalid()
	_test_pcg_constant()
	_test_pcg_add()
	_test_pcg_multiply()
	_test_pcg_clamp()
	_test_pcg_clamp_inverted_bounds()
	_test_pcg_terrace()
	_test_pcg_validation_input_missing()
	_test_pcg_output_unique()
	_test_pcg_cycles_rejected()
	_test_pcg_bad_ports()
	_test_pcg_output_cannot_source()
	_test_pcg_replace_input_link()
	_test_pcg_disconnect()
	_test_pcg_remove_node()
	_test_pcg_duplicate_id_invalid()
	_test_pcg_dangling_link_invalid()
	_test_pcg_invalid_numeric()
	_test_pcg_parameters_validation()
	_test_pcg_node_position()
	_test_pcg_graph_order_independence()
	_test_pcg_noise_determinism()
	_test_pcg_noise_seed_change()
	_test_pcg_noise_frequency()
	_test_pcg_bake_constant()
	_test_pcg_bake_preserves_paint()
	_test_pcg_bake_rejects_invalid_graph()
	_test_pcg_bake_noise_consistency()
	_test_pcg_bake_rebuilds_mesh()
	_test_pcg_resource_serialization()
	_test_world_plan_order()
	_test_world_plan_deduplication()
	_test_world_plan_radius_filter()
	_test_world_plan_negative_coordinates()
	_test_world_initial_state()
	_test_world_sync_spawn()
	_test_world_sync_budget()
	_test_world_hysteresis()
	_test_world_unload()
	_test_world_shared_scene()
	_test_world_invalid_root()
	_test_world_no_duplicate_spawns()
	_test_world_parent_transform()
	_test_world_threaded_request()
	_test_world_signals()
	_test_world_explicit_entries_only()
	_test_world_cell_authorization()
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

func _pcg_constant_output(value: float) -> OWPCGGraph:
	var graph := PCG.new() as OWPCGGraph
	var number := graph.add_node("Constant")
	graph.set_parameter(number, "value", value)
	var output := graph.add_node("Output")
	graph.connect_nodes(number, output, 0)
	return graph


func _pcg_math(kind: String, a: float, b: float) -> OWPCGGraph:
	var graph := PCG.new() as OWPCGGraph
	var first := graph.add_node("Constant")
	var second := graph.add_node("Constant")
	var operation := graph.add_node(kind)
	var output := graph.add_node("Output")
	graph.set_parameter(first, "value", a)
	graph.set_parameter(second, "value", b)
	graph.connect_nodes(first, operation, 0)
	graph.connect_nodes(second, operation, 1)
	graph.connect_nodes(operation, output, 0)
	return graph


func _test_pcg_default() -> void:
	_case("PCG default graph is a usable noise->output graph")
	var graph := OWPCGGraph.make_default_graph()
	_check(graph.validation_error().is_empty(), "default graph valid")
	_check(graph.nodes.size() == 2 and graph.links.size() == 1, "default graph shape")


func _test_pcg_empty_invalid() -> void:
	_case("PCG empty graph is invalid")
	var graph := PCG.new() as OWPCGGraph
	_check(not graph.validation_error().is_empty(), "empty graph missing Output")
	_check(not graph.bake_to_heightmap(_make_map()), "empty graph cannot bake")


func _test_pcg_constant() -> void:
	_case("PCG constant output evaluation")
	var graph := _pcg_constant_output(7.25)
	_check(graph.validation_error().is_empty(), "constant graph complete")
	_approx(graph.evaluate_point(100.0, -13.0), 7.25, "constant independent of coordinates")


func _test_pcg_add() -> void:
	_case("PCG addition node evaluates both input sockets")
	var graph := _pcg_math("Add", 3.5, -2.0)
	_approx(graph.evaluate_point(0.0, 0.0), 1.5, "sum")


func _test_pcg_multiply() -> void:
	_case("PCG multiplication node evaluates both input sockets")
	var graph := _pcg_math("Multiply", -3.0, 4.0)
	_approx(graph.evaluate_point(0.0, 0.0), -12.0, "product")


func _test_pcg_clamp() -> void:
	_case("PCG clamp limits out-of-range values")
	var graph := _pcg_constant_output(12.0)
	var clamp_id := graph.add_node("Clamp")
	var output_id := int(graph.nodes[1]["id"])
	graph.connect_nodes(1, clamp_id, 0)
	graph.connect_nodes(clamp_id, output_id, 0)
	graph.set_parameter(clamp_id, "maximum", 3.0)
	_approx(graph.evaluate_point(0.0, 0.0), 3.0, "upper clamp")


func _test_pcg_clamp_inverted_bounds() -> void:
	_case("PCG clamp handles inverted editor bounds")
	var graph := _pcg_constant_output(-7.0)
	var clamp_id := graph.add_node("Clamp")
	graph.connect_nodes(1, clamp_id, 0)
	graph.connect_nodes(clamp_id, 2, 0)
	graph.set_parameter(clamp_id, "minimum", 2.0)
	graph.set_parameter(clamp_id, "maximum", -2.0)
	_approx(graph.evaluate_point(0.0, 0.0), -2.0, "inverted clamps use sorted bounds")


func _test_pcg_terrace() -> void:
	_case("PCG terrace quantizes its incoming height")
	var graph := _pcg_constant_output(0.62)
	var terrace := graph.add_node("Terrace")
	graph.connect_nodes(1, terrace, 0)
	graph.connect_nodes(terrace, 2, 0)
	graph.set_parameter(terrace, "steps", 4.0)
	_approx(graph.evaluate_point(0.0, 0.0), 0.5, "terraced output")


func _test_pcg_validation_input_missing() -> void:
	_case("PCG incomplete connections are rejected")
	var graph := PCG.new() as OWPCGGraph
	var output := graph.add_node("Output")
	_check(output > 0, "Output created")
	_check(graph.validation_error().contains("Unconnected"), "missing output input detected")


func _test_pcg_output_unique() -> void:
	_case("PCG enforces a single terminal Output")
	var graph := PCG.new() as OWPCGGraph
	_check(graph.add_node("Output") > 0, "first Output created")
	_check(graph.add_node("Output") == -1, "second Output forbidden")


func _test_pcg_cycles_rejected() -> void:
	_case("PCG rejects directed graph cycles")
	var graph := PCG.new() as OWPCGGraph
	var a := graph.add_node("Clamp")
	var b := graph.add_node("Terrace")
	_check(graph.connect_nodes(a, b, 0), "forward edge accepted")
	_check(not graph.connect_nodes(b, a, 0), "reverse cycle blocked")
	_check(graph.links.size() == 1, "failed connection did not mutate graph")


func _test_pcg_bad_ports() -> void:
	_case("PCG rejects invalid source and target ports")
	var graph := _pcg_constant_output(2.0)
	_check(not graph.connect_nodes(1, 2, -1), "negative socket")
	_check(not graph.connect_nodes(1, 2, 1), "out-of-range socket")
	_check(not graph.connect_nodes(1, 999, 0), "unknown target")
	_check(not graph.connect_nodes(999, 2, 0), "unknown source")
	_check(not graph.connect_nodes(1, 1, 0), "self link")


func _test_pcg_output_cannot_source() -> void:
	_case("PCG prevents links leaving Output nodes")
	var graph := _pcg_constant_output(2.0)
	var clamp_id := graph.add_node("Clamp")
	_check(not graph.connect_nodes(2, clamp_id, 0), "terminal cannot source")


func _test_pcg_replace_input_link() -> void:
	_case("PCG reconnecting an input replaces its former source")
	var graph := _pcg_constant_output(4.0)
	var replacement := graph.add_node("Constant")
	graph.set_parameter(replacement, "value", 9.0)
	_check(graph.connect_nodes(replacement, 2, 0), "reconnect input")
	_check(graph.links.size() == 1, "only one source per input")
	_approx(graph.evaluate_point(0.0, 0.0), 9.0, "new source controls output")


func _test_pcg_disconnect() -> void:
	_case("PCG disconnect removes only matching edge")
	var graph := _pcg_constant_output(5.0)
	_check(not graph.disconnect_nodes(111, 2, 0), "unrelated disconnect ignored")
	_check(graph.disconnect_nodes(1, 2, 0), "existing edge removed")
	_check(graph.links.is_empty(), "no remaining links")
	_check(not graph.validation_error().is_empty(), "now incomplete")


func _test_pcg_remove_node() -> void:
	_case("PCG node removal cleans incoming and outgoing links")
	var graph := _pcg_constant_output(5.0)
	_check(graph.remove_node(1), "constant deleted")
	_check(graph.links.is_empty(), "dependent connections deleted")
	_check(not graph.remove_node(1), "double delete rejected")


func _test_pcg_duplicate_id_invalid() -> void:
	_case("PCG validates malformed serialized duplicate node IDs")
	var graph := _pcg_constant_output(1.0)
	graph.nodes.append(graph.nodes[0].duplicate(true))
	_check(graph.validation_error().contains("Duplicate"), "duplicate ID rejected")


func _test_pcg_dangling_link_invalid() -> void:
	_case("PCG detects dangling references in imported resources")
	var graph := _pcg_constant_output(1.0)
	graph.links.append({"from": 999, "to": 2, "input": 0})
	_check(graph.validation_error().contains("Dangling"), "bad reference rejected")


func _test_pcg_invalid_numeric() -> void:
	_case("PCG rejects non-finite inputs")
	var graph := _pcg_constant_output(3.0)
	_check(not graph.set_parameter(1, "value", INF), "infinite constant rejected")
	_check(not graph.set_parameter(1, "value", NAN), "NaN constant rejected")
	_approx(graph.evaluate_point(INF, 0.0), 0.0, "invalid coordinate no-ops")
	_approx(graph.evaluate_point(0.0, NAN), 0.0, "NaN coordinate no-ops")


func _test_pcg_parameters_validation() -> void:
	_case("PCG parameter editing validates type and range")
	var graph := PCG.new() as OWPCGGraph
	var noise := graph.add_node("Noise")
	var terrace := graph.add_node("Terrace")
	_check(not graph.set_parameter(noise, "frequency", 0.0), "zero frequency rejected")
	_check(not graph.set_parameter(noise, "value", 5.0), "unknown Noise parameter rejected")
	_check(not graph.set_parameter(terrace, "steps", 0.0), "zero terrace steps rejected")
	_check(not graph.set_parameter(terrace, "steps", 257.0), "excessive terrace steps rejected")
	_check(not graph.set_parameter(999, "steps", 4.0), "unknown node rejected")


func _test_pcg_node_position() -> void:
	_case("PCG node positions persist as resource data")
	var graph := _pcg_constant_output(2.0)
	_check(graph.set_node_position(1, Vector2(81.0, -42.0)), "valid position saved")
	_check(graph.get_node_data(1)["position"] == Vector2(81.0, -42.0), "position retrieved")
	_check(not graph.set_node_position(999, Vector2.ZERO), "invalid id rejected")
	_check(graph.add_node("Not A Kind") == -1, "invalid node kind rejected")


func _test_pcg_graph_order_independence() -> void:
	_case("PCG evaluation uses topology, not serialized array order")
	var graph := _pcg_math("Multiply", 2.0, 3.0)
	var expected := graph.evaluate_point(4.0, 9.0)
	graph.nodes.reverse()
	_approx(graph.evaluate_point(4.0, 9.0), expected, "shuffled resources remain correct")


func _test_pcg_noise_determinism() -> void:
	_case("PCG noise evaluation is repeatable")
	var graph := OWPCGGraph.make_default_graph()
	var first := graph.evaluate_point(24.5, 31.75)
	_approx(graph.evaluate_point(24.5, 31.75), first, "same sample repeated")
	var copy := OWPCGGraph.make_default_graph()
	_approx(copy.evaluate_point(24.5, 31.75), first, "same seed across resources")


func _test_pcg_noise_seed_change() -> void:
	_case("PCG global noise seed changes its output")
	var graph := OWPCGGraph.make_default_graph()
	var first := graph.evaluate_point(7.25, 18.0)
	graph.seed += 1
	_check(not is_equal_approx(first, graph.evaluate_point(7.25, 18.0)), "seed modifies generated field")


func _test_pcg_noise_frequency() -> void:
	_case("PCG Noise node frequency is editable")
	var graph := OWPCGGraph.make_default_graph()
	var first := graph.evaluate_point(39.0, 17.0)
	_check(graph.set_parameter(1, "frequency", 0.15), "valid frequency update")
	_check(not is_equal_approx(first, graph.evaluate_point(39.0, 17.0)), "frequency modifies field")


func _test_pcg_bake_constant() -> void:
	_case("PCG baking replaces every terrain height")
	var graph := _pcg_constant_output(5.25)
	var data := _make_map(6, 4)
	_check(graph.bake_to_heightmap(data), "graph bakes")
	_check(data.heights.size() == 24, "size respected")
	for value in data.heights:
		_approx(value, 5.25, "constant grid height")


func _test_pcg_bake_preserves_paint() -> void:
	_case("PCG height generation preserves texture paint data")
	var data := _make_map()
	data.paint(2.0, 2.0, 1.5, 0.9)
	var paint_before := data.blend.duplicate()
	_check(_pcg_constant_output(-1.0).bake_to_heightmap(data), "bake succeeds")
	_check(data.blend == paint_before, "splat mask unchanged")


func _test_pcg_bake_rejects_invalid_graph() -> void:
	_case("PCG invalid graph does not mutate target heightmap")
	var data := _make_map()
	data.set_height(1, 1, 6.0)
	var snapshot := data.heights.duplicate()
	var graph := PCG.new() as OWPCGGraph
	graph.add_node("Output")
	_check(not graph.bake_to_heightmap(data), "incomplete graph refuses bake")
	_check(data.heights == snapshot, "terrain untouched on error")


func _test_pcg_bake_noise_consistency() -> void:
	_case("PCG noise bake is deterministic and respects grid spacing")
	var graph := OWPCGGraph.make_default_graph()
	var data := _make_map(7, 9)
	data.cell_size = 2.0
	_check(graph.bake_to_heightmap(data), "noise bake succeeds")
	_approx(data.get_height(3, 4), graph.evaluate_point(6.0, 8.0), "world-space coordinate consistency")
	var first := data.heights.duplicate()
	_check(graph.bake_to_heightmap(data), "repeat bake succeeds")
	_check(first == data.heights, "repeat bake identical")


func _test_pcg_bake_rebuilds_mesh() -> void:
	_case("PCG output propagates through terrain Resource.changed")
	var terrain := Terrain.new() as OWTerrain3D
	terrain.heightmap = _make_map(3, 3)
	terrain.pcg_graph = _pcg_constant_output(3.0)
	root.add_child(terrain)
	_check(terrain.pcg_graph.bake_to_heightmap(terrain.heightmap), "PCG bake succeeds")
	var arrays := terrain.mesh.surface_get_arrays(0)
	_approx(arrays[Mesh.ARRAY_VERTEX][0].y, 3.0, "rebuild after PCG bake")
	terrain.free()


func _test_pcg_resource_serialization() -> void:
	_case("PCG resource survives save/load with node connections")
	var graph := _pcg_math("Add", 1.25, 2.5)
	graph.set_node_position(3, Vector2(120.0, -80.0))
	var path := "user://test_open_world_pcg.tres"
	var status := ResourceSaver.save(graph, path)
	_check(status == OK, "PCG resource saved")
	if status == OK:
		var loaded := ResourceLoader.load(path, "Resource", ResourceLoader.CACHE_MODE_IGNORE) as OWPCGGraph
		_check(loaded != null, "PCG resource loaded")
		if loaded != null:
			_approx(loaded.evaluate_point(3.0, 4.0), 3.75, "linked expression preserved")
			_check(loaded.get_node_data(3)["position"] == Vector2(120.0, -80.0), "editor node positions restored")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _cell_at(x: int, z: int, path: String = "res://tests/fixtures/world_cell.tscn") -> OWWorldCell:
	var entry := WorldCell.new() as OWWorldCell
	entry.coordinate = Vector2i(x, z)
	entry.scene_path = path
	return entry


func _world_for_tests(threaded: bool = false) -> OWWorldPartition3D:
	var world := WorldPartition.new() as OWWorldPartition3D
	world.threaded_loading = threaded
	world.cell_size = 10.0
	world.load_radius = 1
	world.unload_radius = 2
	world.max_cells_per_update = 8
	return world


func _test_world_plan_order() -> void:
	_case("world streaming loads closer coordinates first")
	var world := _world_for_tests()
	world.cells.append(_cell_at(1, 1))
	world.cells.append(_cell_at(-1, 0))
	world.cells.append(_cell_at(0, 0))
	var planned := world.planned_cells(Vector2i.ZERO)
	_check(planned.size() == 3, "three matching cells")
	_check(planned[0].coordinate == Vector2i.ZERO, "center cell first")
	_check(planned[1].coordinate == Vector2i(-1, 0), "cardinal before diagonal")
	world.free()


func _test_world_plan_deduplication() -> void:
	_case("world streaming deduplicates conflicting authored coordinates")
	var world := _world_for_tests()
	world.cells.append(_cell_at(0, 0))
	world.cells.append(_cell_at(0, 0, "res://tests/fixtures/invalid_world_cell.tscn"))
	var planned := world.planned_cells(Vector2i.ZERO)
	_check(planned.size() == 1, "only one cell per coordinate")
	_check(planned[0].scene_path == "res://tests/fixtures/world_cell.tscn", "first authoring entry wins")
	world.free()


func _test_world_plan_radius_filter() -> void:
	_case("world streaming ignores assets outside load radius")
	var world := _world_for_tests()
	world.cells.append(_cell_at(2, 0))
	world.cells.append(_cell_at(1, 1))
	world.cells.append(_cell_at(0, 1))
	_check(world.planned_cells(Vector2i.ZERO).size() == 2, "square radius filter")
	world.load_radius = 0
	_check(world.planned_cells(Vector2i.ZERO).is_empty(), "zero radius excludes neighbors")
	world.free()


func _test_world_plan_negative_coordinates() -> void:
	_case("world streaming supports negative authored grid coordinates")
	var world := _world_for_tests()
	world.cells.append(_cell_at(-3, -4))
	world.cells.append(_cell_at(3, 4))
	var planned := world.planned_cells(Vector2i(-3, -4))
	_check(planned.size() == 1, "one matching negative cell")
	_check(planned[0].coordinate == Vector2i(-3, -4), "negative target retained")
	world.free()


func _test_world_initial_state() -> void:
	_case("world streamer begins empty")
	var world := _world_for_tests()
	_check(world.active_cell_count() == 0, "no active cells")
	_check(world.pending_resource_count() == 0, "no pending requests")
	_check(not world.is_cell_active(Vector2i.ZERO), "no active origin")
	world.free()


func _test_world_sync_spawn() -> void:
	_case("world streamer instantiates a valid authored scene")
	var world := _world_for_tests()
	world.cells.append(_cell_at(0, 0))
	root.add_child(world)
	world.update_streaming(Vector3.ZERO)
	_check(world.active_cell_count() == 1, "one cell instantiated")
	_check(world.is_cell_active(Vector2i.ZERO), "origin cell loaded")
	_check(world.get_child_count() == 1, "one child scene instantiated")
	world.free()


func _test_world_sync_budget() -> void:
	_case("world streamer respects per-update loading budgets")
	var world := _world_for_tests()
	world.max_cells_per_update = 1
	world.cells.append(_cell_at(1, 0))
	world.cells.append(_cell_at(0, 0))
	world.cells.append(_cell_at(0, 1))
	root.add_child(world)
	world.update_streaming(Vector3.ZERO)
	_check(world.active_cell_count() == 1, "first update loads one")
	_check(world.is_cell_active(Vector2i.ZERO), "center gets priority")
	world.update_streaming(Vector3.ZERO)
	_check(world.active_cell_count() == 2, "second update loads second")
	world.update_streaming(Vector3.ZERO)
	_check(world.active_cell_count() == 3, "third update loads third")
	world.free()


func _test_world_hysteresis() -> void:
	_case("world streamer retains cells between load/unload radii")
	var world := _world_for_tests()
	world.cells.append(_cell_at(0, 0))
	root.add_child(world)
	world.update_streaming(Vector3.ZERO)
	world.update_streaming(Vector3(20.0, 0.0, 0.0))
	_check(world.is_cell_active(Vector2i.ZERO), "cell inside unload radius stays loaded")
	world.free()


func _test_world_unload() -> void:
	_case("world streamer releases distant cells")
	var world := _world_for_tests()
	world.cells.append(_cell_at(0, 0))
	root.add_child(world)
	world.update_streaming(Vector3.ZERO)
	world.update_streaming(Vector3(30.0, 0.0, 0.0))
	_check(world.active_cell_count() == 0, "cell removed beyond unload radius")
	_check(not world.is_cell_active(Vector2i.ZERO), "no active origin")
	world.free()


func _test_world_shared_scene() -> void:
	_case("world cells referencing one PackedScene get separate instances")
	var world := _world_for_tests()
	world.cells.append(_cell_at(0, 0))
	world.cells.append(_cell_at(1, 0))
	root.add_child(world)
	world.update_streaming(Vector3.ZERO)
	_check(world.active_cell_count() == 2, "two active cells")
	_check(world.get_child_count() == 2, "same scene instantiated twice")
	world.free()


func _test_world_invalid_root() -> void:
	_case("world streamer rejects non-Node3D PackedScene root")
	var world := _world_for_tests()
	world.cells.append(_cell_at(0, 0, "res://tests/fixtures/invalid_world_cell.tscn"))
	root.add_child(world)
	world.update_streaming(Vector3.ZERO)
	_check(world.active_cell_count() == 0, "invalid root not active")
	world.free()


func _test_world_no_duplicate_spawns() -> void:
	_case("world streamer never instantiates an active cell twice")
	var world := _world_for_tests()
	world.cells.append(_cell_at(0, 0))
	root.add_child(world)
	for i in 4:
		world.update_streaming(Vector3.ZERO)
	_check(world.active_cell_count() == 1, "one active record")
	_check(world.get_child_count() == 1, "one instantiated node")
	world.free()


func _test_world_parent_transform() -> void:
	_case("world streamer offsets cell scenes relative to parent transform")
	var world := _world_for_tests()
	world.position = Vector3(100, 5, -80)
	world.cells.append(_cell_at(-1, 2))
	root.add_child(world)
	world.update_streaming(Vector3(90, 5, -60))
	_check(world.world_to_cell(Vector3(90, 5, -60)) == Vector2i(-1, 2), "global to local grid mapping")
	_check(world.is_cell_active(Vector2i(-1, 2)), "translated cell active")
	if world.get_child_count() > 0:
		_check(world.get_child(0).global_position.is_equal_approx(Vector3(90, 5, -60)), "scene aligned with parent")
	world.free()


func _test_world_threaded_request() -> void:
	_case("world streamer queues scene assets for threaded loading")
	var world := _world_for_tests(true)
	world.cells.append(_cell_at(0, 0))
	world.cells.append(_cell_at(1, 0))
	root.add_child(world)
	world.update_streaming(Vector3.ZERO)
	_check(world.pending_resource_count() == 1, "same scene path shares one pending request")
	_check(world.active_cell_count() == 0, "no synchronous instantiation")
	world.free()


func _test_world_signals() -> void:
	_case("world streamer emits load and unload notifications")
	var world := _world_for_tests()
	var loaded: Array[Vector2i] = []
	var unloaded: Array[Vector2i] = []
	world.cell_loaded.connect(func(coord: Vector2i, _instance: Node3D): loaded.append(coord))
	world.cell_unloaded.connect(func(coord: Vector2i): unloaded.append(coord))
	world.cells.append(_cell_at(0, 0))
	root.add_child(world)
	world.update_streaming(Vector3.ZERO)
	world.update_streaming(Vector3(30, 0, 0))
	_check(loaded == [Vector2i.ZERO], "load signal once")
	_check(unloaded == [Vector2i.ZERO], "unload signal once")
	world.free()


func _test_world_explicit_entries_only() -> void:
	_case("world streamer will not invent content without authored resources")
	var world := _world_for_tests()
	root.add_child(world)
	world.update_streaming(Vector3.ZERO)
	_check(world.active_cell_count() == 0, "no automatic child scenes")
	world.free()


func _test_world_cell_authorization() -> void:
	_case("world streamer avoids obsolete pending cell definitions")
	var world := _world_for_tests()
	world.cells.append(_cell_at(1, 2))
	_check(world._is_authorized(Vector2i(1, 2), "res://tests/fixtures/world_cell.tscn"), "matching path authorized")
	_check(not world._is_authorized(Vector2i(1, 2), "res://tests/fixtures/invalid_world_cell.tscn"), "replaced path rejected")
	world.cells.clear()
	_check(not world._is_authorized(Vector2i(1, 2), "res://tests/fixtures/world_cell.tscn"), "removed entry rejected")
	world.free()
