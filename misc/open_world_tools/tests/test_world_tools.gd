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