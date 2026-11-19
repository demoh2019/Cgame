extends SceneTree
## Headless regression harness: godot --headless --path . --script res://tests/test_world_tools.gd

const Terrain = preload("res://addons/open_world_tools/world_terrain_3d.gd")
const Foliage = preload("res://addons/open_world_tools/world_foliage_3d.gd")
const Cell = preload("res://addons/open_world_tools/world_stream_cell.gd")
const Streamer = preload("res://addons/open_world_tools/world_streamer_3d.gd")

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("TEST FAILED: " + message)


func _close(a: float, b: float, tolerance: float = 0.001) -> bool:
	return absf(a - b) <= tolerance


func _run() -> void:
	_test_heightmap()
	_test_brushes()
	_test_erosion()
	_test_foliage()
	_test_streamer()
	_test_storage_and_mesh_invariants()
	_test_invalid_brush_and_snapshots()
	_test_erosion_extremes()
	_test_foliage_world_space_and_slope()
	_test_streamer_boundaries()
	print("Open World Tools: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _new_terrain() -> WorldTerrain3D:
	var t: WorldTerrain3D = Terrain.new()
	t.resolution = 5
	t.cell_size = 1.0
	t.chunk_cells = 2
	root.add_child(t)
	return t


func _test_heightmap() -> void:
	var t: WorldTerrain3D = _new_terrain()
	_check(t.height_data.size() == 25, "5x5 heightmap allocated")
	_check(t.color_data.size() == 25, "5x5 color map allocated")
	_check(t.weight_data.size() == 25, "5x5 texture layer weights allocated")
	_check(t.sample_index(3, 2) == 13, "row-major indexing")
	_check(t.contains_xz(0.0, 4.0), "edge included")
	_check(not t.contains_xz(-0.1, 1.0), "negative X rejected")
	_check(not t.contains_xz(4.1, 1.0), "beyond right edge rejected")
	_check(not t.contains_xz(0.0, 4.1), "beyond bottom edge rejected")
	t.height_data[t.sample_index(0, 0)] = 0.0
	t.height_data[t.sample_index(1, 0)] = 2.0
	t.height_data[t.sample_index(0, 1)] = 4.0
	t.height_data[t.sample_index(1, 1)] = 6.0
	_check(_close(t.get_height_at(0.5, 0.5), 3.0), "bilinear height sample")
	_check(_close(t.get_height_at(1.0, 0.0), 2.0), "exact grid sample")
	_check(_close(t.get_height_at(-5.0, 0.0), 0.0), "height sample clamps negative X")
	_check(t.get_normal_at(2.0, 2.0).y > 0.0, "normal points upward")
	t.rebuild()
	var generated: Node3D = t.get_node_or_null(t.GENERATED_NAME) as Node3D
	_check(generated != null, "generated mesh container exists")
	if generated != null:
		_check(generated.get_child_count() == 4, "4 chunks produced from a 5x5 grid with chunk size 2")
		for chunk in generated.get_children():
			_check((chunk as MeshInstance3D).mesh.get_surface_count() == 1, "chunk contains mesh surface")
	var saved: PackedFloat32Array = t.height_data.duplicate()
	var colors: PackedColorArray = t.color_data.duplicate()
	saved[0] = 13.0
	t.restore_samples(saved, colors)
	_check(_close(t.get_height_at(0, 0), 13.0), "restore snapshot")
	_check(t.height_data.size() == 25, "restore preserves array size")
	# Heightmap import should resample 2x2 luminance data into 5x5 heights.
	var image: Image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, Color.BLACK)
	image.set_pixel(1, 0, Color.WHITE)
	image.set_pixel(0, 1, Color.WHITE)
	image.set_pixel(1, 1, Color.BLACK)
	_check(t.import_heightmap(image, 10.0), "heightmap import succeeds")
	_check(_close(t.get_height_at(0.0, 0.0), 0.0), "dark pixel maps to zero")
	_check(_close(t.get_height_at(4.0, 0.0), 10.0), "white pixel maps to max elevation")
	_check(not t.import_heightmap(null, 10.0), "null heightmap rejected")
	_check(not t.import_heightmap(image, -1.0), "negative heightmap scale rejected")
	t.use_texture_layers = true
	t.rebuild()
	var chunk: MeshInstance3D = (t.get_node(t.GENERATED_NAME) as Node3D).get_child(0) as MeshInstance3D
	_check(chunk.material_override is ShaderMaterial, "splat mapping uses ShaderMaterial")
	t.free()


func _test_brushes() -> void:
	var t: WorldTerrain3D = _new_terrain()
	var empty: int = t.apply_brush(Vector3(2.0, 0.0, 2.0), 0.0, 3.0, Terrain.BrushMode.RAISE)
	_check(empty == 0, "zero radius does nothing")
	_check(t.apply_brush(Vector3(2.0, 0.0, 2.0), 2.0, 0.0, Terrain.BrushMode.RAISE) == 0, "zero strength does nothing")
	var baseline: PackedFloat32Array = t.height_data.duplicate()
	var baseline_colors: PackedColorArray = t.color_data.duplicate()
	var baseline_weights: PackedColorArray = t.weight_data.duplicate()
	_check(t.apply_brush(Vector3(2, 0, 2), 1.5, 4.0, Terrain.BrushMode.RAISE) > 0, "raise modifies samples")
	_check(_close(t.get_height_at(2, 2), 4.0), "raise center receives full strength")
	_check(_close(t.get_height_at(0, 0), 0.0), "raise leaves distant samples untouched")
	_check(t.apply_brush(Vector3(2, 0, 2), 1.0, -2.0, Terrain.BrushMode.RAISE) > 0, "negative raise lowers terrain")
	_check(_close(t.get_height_at(2, 2), 2.0), "lower subtracts amount")
	_check(t.apply_brush(Vector3(2, 0, 2), 1.0, 1.0, Terrain.BrushMode.FLATTEN, 10.0) > 0, "flatten modifies terrain")
	_check(_close(t.get_height_at(2, 2), 10.0), "flatten center reaches target")
	_check(t.apply_brush(Vector3(2, 0, 2), 1.0, 1.0, Terrain.BrushMode.SMOOTH) > 0, "smooth modifies terrain")
	_check(t.get_height_at(2, 2) < 10.0, "smooth averages elevated sample")
	var brown: Color = Color(0.5, 0.2, 0.1)
	_check(t.apply_brush(Vector3(2, 0, 2), 1.0, 1.0, Terrain.BrushMode.PAINT, 0.0, brown) > 0, "paint modifies samples")
	_check(t.color_data[t.sample_index(2, 2)].is_equal_approx(brown), "paint center reaches chosen color")
	_check(t.color_data[t.sample_index(0, 0)].is_equal_approx(t.DEFAULT_COLOR), "paint does not touch distant color")
	_check(t.apply_brush(Vector3(2, 0, 2), 1.0, 1.0, Terrain.BrushMode.PAINT_TEXTURE_LAYER, 0.0, Color.WHITE, 2) > 0, "texture paint modifies weights")
	_check(t.weight_data[t.sample_index(2, 2)].is_equal_approx(Color(0.0, 0.0, 1.0, 0.0)), "layer 2 receives full weight")
	_check(t.weight_data[t.sample_index(0, 0)].is_equal_approx(t.DEFAULT_WEIGHTS), "distant weights unchanged")
	_check(t.apply_brush(Vector3(2, 0, 2), 1.0, 1.0, Terrain.BrushMode.PAINT_TEXTURE_LAYER, 0.0, Color.WHITE, 9) == 0, "invalid texture channel rejected")
	t.restore_samples(baseline, baseline_colors, baseline_weights)
	_check(_close(t.get_height_at(2, 2), 0.0), "undo snapshot restores height")
	_check(t.color_data[t.sample_index(2, 2)].is_equal_approx(t.DEFAULT_COLOR), "undo snapshot restores color")
	_check(t.weight_data[t.sample_index(2, 2)].is_equal_approx(t.DEFAULT_WEIGHTS), "undo snapshot restores texture weights")
	var invalid: PackedFloat32Array = PackedFloat32Array([1.0])
	t.restore_samples(invalid, baseline_colors)
	_check(t.height_data.size() == 25, "wrong-length snapshot ignored")
	t.free()


func _sum_heights(t: WorldTerrain3D) -> float:
	var total: float = 0.0
	for h in t.height_data:
		total += h
	return total


func _test_erosion() -> void:
	var t: WorldTerrain3D = _new_terrain()
	t.height_data[t.sample_index(2, 2)] = 40.0
	var before: float = _sum_heights(t)
	t.erode_thermal(0, 1.0, 0.5)
	_check(_close(_sum_heights(t), before), "zero-iteration erosion unchanged")
	t.erode_thermal(1, 1.0, 0.0)
	_check(_close(_sum_heights(t), before), "zero-rate erosion unchanged")
	t.erode_thermal(10, 1.0, 0.7)
	_check(_close(_sum_heights(t), before, 0.01), "erosion approximately conserves mass")
	_check(t.height_data[t.sample_index(2, 2)] < 40.0, "erosion reduces peak")
	_check(t.height_data[t.sample_index(2, 1)] > 0.0, "erosion deposits to neighbor")
	_check(t.height_data[t.sample_index(1, 2)] > 0.0, "erosion deposits in other axis")
	t.free()


func _test_foliage() -> void:
	var t: WorldTerrain3D = _new_terrain()
	var f: WorldFoliage3D = Foliage.new()
	root.add_child(f)
	f.terrain = t
	f.placement_count = 24
	f.random_seed = 2001
	_check(f.scatter() == 0, "missing source mesh produces no foliage")
	f.foliage_mesh = BoxMesh.new()
	_check(f.scatter() == 24, "flat terrain accepts all 24 plants")
	_check(f.multimesh.instance_count == 24, "MultiMesh instance count matches placement")
	var first: Transform3D = f.multimesh.get_instance_transform(0)
	f.scatter()
	_check(f.multimesh.get_instance_transform(0).is_equal_approx(first), "seed generates deterministic transforms")
	_check(f.multimesh.get_instance_transform(1).origin != first.origin, "foliage instances do not all overlap")
	f.placement_count = 0
	_check(f.scatter() == 0, "zero requested foliage produces none")
	_check(f.multimesh.instance_count == 0, "empty MultiMesh is valid")
	f.terrain = null
	_check(f.scatter() == 0 and f.multimesh == null, "missing terrain clears foliage")
	f.free()
	t.free()


func _make_cell(coord: Vector2i) -> WorldStreamCell:
	var root_node: Node3D = Node3D.new()
	var packed: PackedScene = PackedScene.new()
	var packed_result: Error = packed.pack(root_node)
	_check(packed_result == OK, "test cell scene packs")
	root_node.free()
	var cell: WorldStreamCell = Cell.new()
	cell.grid_coord = coord
	cell.scene = packed
	return cell


func _test_streamer() -> void:
	var focus: Node3D = Node3D.new()
	root.add_child(focus)
	var streamer: WorldStreamer3D = Streamer.new()
	streamer.focus = focus
	streamer.cell_size = 10.0
	streamer.active_radius = 0
	streamer.cells = [_make_cell(Vector2i.ZERO), _make_cell(Vector2i(1, 0)), _make_cell(Vector2i(-1, 0))]
	root.add_child(streamer)
	streamer.update_streaming()
	_check(streamer.get_loaded_cell_count() == 1, "only origin cell loads at radius 0")
	streamer.update_streaming()
	_check(streamer.get_loaded_cell_count() == 1, "idempotent update does not duplicate cells")
	focus.position = Vector3(14, 0, 0)
	streamer.update_streaming()
	_check(streamer.get_loaded_cell_count() == 1, "moving into next cell replaces loaded cell")
	focus.position = Vector3(-0.01, 0, 0)
	streamer.update_streaming()
	_check(streamer.get_loaded_cell_count() == 1, "negative coordinates use floor, not truncation")
	streamer.active_radius = 2
	streamer.update_streaming()
	_check(streamer.get_loaded_cell_count() == 3, "radius 2 includes all three registered cells")
	streamer.focus = null
	streamer.update_streaming()
	_check(streamer.get_loaded_cell_count() == 0, "missing focus unloads cells")
	streamer.free()
	focus.free()


func _test_storage_and_mesh_invariants() -> void:
	var t: WorldTerrain3D = _new_terrain()
	# Reinitialization must preserve valid data and reject corrupt lengths.
	t.height_data[3] = 2.75
	t.initialize_storage()
	_check(_close(t.height_data[3], 2.75), "valid height samples survive reinitialize")
	t.height_data = PackedFloat32Array([9.0])
	t.color_data = PackedColorArray([Color.RED])
	t.weight_data = PackedColorArray([Color.GREEN])
	t.initialize_storage()
	_check(t.height_data.size() == 25 and _close(t.height_data[3], 0.0), "invalid height map repaired")
	_check(t.color_data.size() == 25 and t.color_data[3].is_equal_approx(t.DEFAULT_COLOR), "invalid color map repaired")
	_check(t.weight_data.size() == 25 and t.weight_data[3].is_equal_approx(t.DEFAULT_WEIGHTS), "invalid weights repaired")
	_check(t.get_normal_at(2.0, 2.0).is_equal_approx(Vector3.UP), "flat terrain normal is up")
	t.rebuild()
	var generated: Node3D = t.get_node(t.GENERATED_NAME) as Node3D
	_check(generated.get_child_count() == 4, "full 2x2 chunk topology")
	for chunk in generated.get_children():
		var m: ArrayMesh = (chunk as MeshInstance3D).mesh as ArrayMesh
		_check(m.surface_get_array_len(0) == 24, "2x2 quad mesh has 24 vertices")
		_check(chunk.get_child_count() == 0, "collision disabled by default")
	t.enable_collision = true
	t.rebuild()
	generated = t.get_node(t.GENERATED_NAME) as Node3D
	for chunk in generated.get_children():
		_check(chunk.get_child_count() == 1, "collision enabled creates static body")
		var body: StaticBody3D = chunk.get_child(0) as StaticBody3D
		_check(body != null and body.get_child_count() == 1, "collision has one shape")
		temp_collision_check(body)
	t.enable_collision = false
	t.rebuild()
	generated = t.get_node(t.GENERATED_NAME) as Node3D
	_check(generated.get_child(0).get_child_count() == 0, "disabling collision removes physics bodies")
	t.resolution = 3
	t.cell_size = 0.0
	t.chunk_cells = 1
	t.initialize_storage()
	_check(t.resolution == 3 and t.height_data.size() == 9, "resizing reallocates heightfield")
	_check(t.cell_size > 0.0, "nonpositive cell size is clamped")
	_check(t.chunk_cells == 2, "too small chunk size is clamped")
	t.rebuild()
	_check((t.get_node(t.GENERATED_NAME) as Node3D).get_child_count() == 1, "resized terrain creates one chunk")
	t.free()


func temp_collision_check(body: StaticBody3D) -> void:
	var shape: CollisionShape3D = body.get_child(0) as CollisionShape3D
	_check(shape != null and shape.shape != null, "generated collision shape is nonempty")


func _test_invalid_brush_and_snapshots() -> void:
	var t: WorldTerrain3D = _new_terrain()
	var initial: PackedFloat32Array = t.height_data.duplicate()
	var colors: PackedColorArray = t.color_data.duplicate()
	var weights: PackedColorArray = t.weight_data.duplicate()
	_check(t.apply_brush(Vector3(2, 0, 2), 2.0, 2.0, -1) == 0, "unknown negative brush mode rejected")
	_check(t.apply_brush(Vector3(2, 0, 2), 2.0, 2.0, 999) == 0, "unknown positive brush mode rejected")
	_check(t.apply_brush(Vector3(2, 0, 2), 1.0, 1.0, Terrain.BrushMode.PAINT_TEXTURE_LAYER, 0.0, Color.WHITE, -1) == 0, "negative texture channel rejected")
	_check(t.apply_brush(Vector3(2, 0, 2), 1.0, 1.0, Terrain.BrushMode.PAINT_TEXTURE_LAYER, 0.0, Color.WHITE, 4) == 0, "out-of-range texture channel rejected")
	_check(t.apply_brush(Vector3(2, 0, 2), 1.0, -1.0, Terrain.BrushMode.PAINT) == 0, "negative paint strength rejected")
	_check(t.apply_brush(Vector3(100, 0, 100), 1.0, 1.0, Terrain.BrushMode.RAISE) == 0, "off-grid brush has no effect")
	_check(t.height_data == initial, "invalid brushes leave terrain heights untouched")
	_check(t.color_data == colors, "invalid brushes leave colors untouched")
	_check(t.weight_data == weights, "invalid brushes leave weights untouched")
	_check(t.apply_brush(Vector3(2, 0, 2), 1.0, 0.5, Terrain.BrushMode.PAINT_TEXTURE_LAYER, 0.0, Color.WHITE, 1) > 0, "partial texture paint succeeds")
	var w: Color = t.weight_data[t.sample_index(2, 2)]
	_check(_close(w.r, 0.5) and _close(w.g, 0.5), "partial texture paint blends source and target")
	_check(_close(w.r + w.g + w.b + w.a, 1.0), "texture weights conserve unity after painting")
	var updated: PackedColorArray = t.weight_data.duplicate()
	t.restore_samples(initial, colors, PackedColorArray([Color.RED]))
	_check(t.weight_data == updated, "mismatched weight snapshot does not corrupt terrain")
	t.restore_samples(initial, colors, weights)
	_check(t.weight_data == weights, "undo restores all four weight channels")
	initial[0] = 123.0
	_check(_close(t.height_data[0], 0.0), "restored height arrays do not alias source snapshots")
	t.free()


func _test_erosion_extremes() -> void:
	var t: WorldTerrain3D = _new_terrain()
	var flat: PackedFloat32Array = t.height_data.duplicate()
	t.erode_thermal(5, 0.0, 1.0)
	_check(t.height_data == flat, "flat terrain remains flat during erosion")
	t.height_data[t.sample_index(2, 2)] = 27.0
	var before: PackedFloat32Array = t.height_data.duplicate()
	t.erode_thermal(-5, 0.0, 1.0)
	_check(t.height_data == before, "negative erosion iterations do nothing")
	t.erode_thermal(4, 1000.0, 1.0)
	_check(t.height_data == before, "large talus prevents material transfer")
	t.erode_thermal(4, 0.0, -1.0)
	_check(t.height_data == before, "negative erosion rate rejected")
	var conserved: float = _sum_heights(t)
	for rate in [0.25, 0.5, 1.0, 3.0]:
		t.height_data = before.duplicate()
		t.erode_thermal(8, 0.0, rate)
		_check(_close(_sum_heights(t), conserved, 0.005), "erosion conserves mass at rate %f" % rate)
		_check(t.height_data[t.sample_index(2, 2)] < 27.0, "erosion reduces peak at rate %f" % rate)
	t.free()


func _test_foliage_world_space_and_slope() -> void:
	var t: WorldTerrain3D = _new_terrain()
	t.position = Vector3(70.0, 9.0, -40.0)
	var f: WorldFoliage3D = Foliage.new()
	root.add_child(f)
	f.position = Vector3(-12.0, 4.0, 50.0)
	f.terrain = t
	f.foliage_mesh = SphereMesh.new()
	f.placement_count = 16
	f.random_seed = 9101
	f.min_instance_scale = 0.8
	f.max_instance_scale = 0.8
	_check(f.scatter() == 16, "transformed foliage accepts all locations on flat terrain")
	var first_set: Array[Transform3D] = []
	for i in range(f.multimesh.instance_count):
		var tr: Transform3D = f.multimesh.get_instance_transform(i)
		first_set.append(tr)
		var world_origin: Vector3 = f.global_transform * tr.origin
		_check(world_origin.x >= 69.999 and world_origin.x <= 74.001, "foliage world X stays in terrain bounds")
		_check(world_origin.z >= -40.001 and world_origin.z <= -35.999, "foliage world Z stays in terrain bounds")
		_check(_close(world_origin.y, 9.0), "foliage world Y matches terrain elevation")
		_check(_close(tr.basis.get_scale().x, 0.8), "fixed foliage instance scale respected")
	f.scatter()
	for i in range(f.multimesh.instance_count):
		_check(f.multimesh.get_instance_transform(i).is_equal_approx(first_set[i]), "all foliage transforms deterministic under fixed seed")
	f.random_seed = 9102
	f.scatter()
	_check(not f.multimesh.get_instance_transform(0).is_equal_approx(first_set[0]), "different seeds change positions")
	for z in range(t.resolution):
		for x in range(t.resolution):
			t.height_data[t.sample_index(x, z)] = float(x) * 10.0
	f.max_slope_degrees = 0.0
	_check(f.scatter() == 0, "zero slope tolerance rejects a steep plane")
	_check(f.multimesh.instance_count == 0, "slope filtering returns empty MultiMesh")
	f.free()
	t.free()


func _test_streamer_boundaries() -> void:
	var focus: Node3D = Node3D.new()
	root.add_child(focus)
	var streamer: WorldStreamer3D = Streamer.new()
	root.add_child(streamer)
	streamer.focus = focus
	streamer.cell_size = 10.0
	streamer.active_radius = 0
	streamer.cells = [
		_make_cell(Vector2i(-1, -1)),
		_make_cell(Vector2i(0, 0)),
		_make_cell(Vector2i(1, 1)),
		_make_cell(Vector2i(0, 1)),
		_make_cell(Vector2i(1, 0)),
		_make_cell(Vector2i.ZERO)
	]
	focus.position = Vector3(-0.001, 0, -0.001)
	streamer.update_streaming()
	_check(streamer.get_loaded_cell_count() == 1, "negative coordinates load negative quadrant")
	focus.position = Vector3(10.0, 0, 10.0)
	streamer.update_streaming()
	_check(streamer.get_loaded_cell_count() == 1, "positive exact cell boundary loads next quadrant")
	focus.position = Vector3.ZERO
	streamer.update_streaming()
	_check(streamer.get_loaded_cell_count() == 1, "duplicate grid cells never load twice")
	streamer.active_radius = 1
	streamer.update_streaming()
	_check(streamer.get_loaded_cell_count() == 5, "radius one loads all valid nearby grid cells")
	streamer.cell_size = 0.0
	streamer.update_streaming()
	_check(streamer.get_loaded_cell_count() == 0, "zero-size stream cells clear content safely")
	streamer.cell_size = 10.0
	streamer.update_streaming()
	_check(streamer.get_loaded_cell_count() == 5, "streaming resumes after cell size becomes valid")
	var no_scene: WorldStreamCell = Cell.new()
	no_scene.grid_coord = Vector2i(4, 4)
	streamer.cells.append(no_scene)
	streamer.update_streaming()
	_check(streamer.get_loaded_cell_count() == 5, "empty cell scenes are ignored")
	streamer.clear_loaded()
	_check(streamer.get_loaded_cell_count() == 0, "explicit clear removes loaded entries")
	streamer.update_streaming()
	_check(streamer.get_loaded_cell_count() == 5, "streamer can repopulate after explicit clear")
	streamer.focus = null
	streamer.update_streaming()
	_check(streamer.get_loaded_cell_count() == 0, "unset focus safely unloads all cells")
	streamer.free()
	focus.free()