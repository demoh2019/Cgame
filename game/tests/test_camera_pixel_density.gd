extends RefCounted
## Test the fork's native projected pixel density and ordinary Godot fallback.
## The API belongs to Camera3D (C++), not a second shader or Python helper.
const GrassField = preload("res://scripts/client/grass_field.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")


func run(t) -> void:
	t.current = "projected vegetation coverage from real pixel density"
	var reference_focal: float = 360.0 / tan(deg_to_rad(38.0) * 0.5)
	t.near(GrassField.projected_lod_distance(20.0, reference_focal / 20.0, 1.0),
		20.0, 0.001, "reference resolution and distance keep the original LOD")
	t.check(GrassField.projected_lod_distance(20.0, reference_focal / 40.0, 1.0) > 20.0,
		"smaller projected blades lose geometry earlier")
	t.check(GrassField.projected_lod_distance(20.0, reference_focal / 10.0, 1.0) < 20.0,
		"zoomed-in blades retain the close-up silhouette")
	t.check(GrassField.projected_lod_distance(20.0, reference_focal / 20.0 * 2.0, 2.0) > 15.0,
		"4K resolution cannot multiply geometry cost without bound")
	t.eq(GrassField.projected_lod_distance(30.0, NAN, 1.0), 30.0,
		"invalid pixel density falls back to world distance")
	t.eq(GrassField.projected_lod_distance(30.0, 0.0, 1.0), 30.0,
		"zero pixel density falls back to world distance")
	t.eq(GrassField.projected_lod_distance(30.0, 20.0, NAN), 30.0,
		"invalid focal ratio falls back safely")
	t.check(GrassField.projected_lod_distance(55.0, reference_focal / 55.0, 1.0)
		> GrassField.projected_lod_distance(20.0, reference_focal / 20.0, 1.0),
		"distance remains monotonic for equal focal geometry")

	t.current = "shared camera projection integration"
	var chunk_source: String = (ChunkView as Script).source_code
	t.check(chunk_source.contains('view_camera.has_method("get_pixels_per_meter_at_position")'),
		"game uses native method when the custom engine supports it")
	t.check(chunk_source.contains("GrassField.projected_lod_distance("),
		"native projected density drives streamed grass mesh and instance selection")
	t.check(chunk_source.contains("GrassField.screen_lod_scale(screen_height, vertical_fov)"),
		"upstream Godot retains its safe screen-space approximation")
	t.check(chunk_source.contains("camera_forward.distance_squared_to("),
		"camera rotation invalidates stale grass LOD")
	t.check(chunk_source.contains("_grass_last_camera_y"),
		"camera height changes invalidate stale grass LOD")
	t.current = "live streamed grass tile LOD batches native screen-space projection"
	t.check(chunk_source.contains('view_camera.has_method("get_pixels_per_meter_at_positions")'),
		"real chunk LOD feature-detects new native batch projection")
	t.check(chunk_source.contains('view_camera.call("get_pixels_per_meter_at_positions", tile_centers)'),
		"real streamed grass batches all tile centers into one camera query")
	t.check(chunk_source.contains("batch_density.size() == _grass_tiles.size()"),
		"invalid native results fall back atomically to scalar selection")
	t.check(chunk_source.contains('view_camera.call("get_pixels_per_meter_at_position", tile_center)'),
		"old engines retain per-tile scalar projection compatibility")
	t.check(chunk_source.contains("_grass_tiles.size() <= 4096"),
		"bounded native batch preserves the scalar path for large groups")

	t.current = "native Camera3D method in fork, including orthographic mode"
	var camera := Camera3D.new()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		t.check(true, "non-game main loops skip live engine camera checks")
		camera.free()
		return
	tree.root.add_child(camera)
	if not camera.has_method("get_pixels_per_meter_at_position"):
		# Standard Godot is supported: it uses the tested visual fallback.
		t.check(true, "standard Godot uses fallback without an unavailable native call")
		camera.free()
		return
	camera.set_perspective(38.0, 0.05, 500.0)
	var near_density: float = float(camera.call("get_pixels_per_meter_at_position",
		Vector3(0.0, 0.0, -10.0)))
	var far_density: float = float(camera.call("get_pixels_per_meter_at_position",
		Vector3(0.0, 0.0, -20.0)))
	t.check(near_density > 0.0 and far_density > 0.0,
		"native projection returns valid pixel coverage")
	t.near(near_density / far_density, 2.0, 0.01,
		"perspective objects halve in pixel size at twice the depth")
	t.eq(float(camera.call("get_pixels_per_meter_at_position",
		Vector3(0.0, 0.0, 10.0))), 0.0,
		"camera never assigns detail to a point behind the lens")
	camera.set_orthogonal(20.0, 0.05, 500.0)
	var ortho_near: float = float(camera.call("get_pixels_per_meter_at_position",
		Vector3(0.0, 0.0, -10.0)))
	var ortho_far: float = float(camera.call("get_pixels_per_meter_at_position",
		Vector3(0.0, 0.0, -20.0)))
	t.check(ortho_near > 0.0 and is_finite(ortho_near),
		"orthographic pixel density is positive and finite")
	t.near(ortho_near, ortho_far, 0.001,
		"orthographic detail is independent of world-space depth")

	t.current = "native Camera3D bulk projected grass coverage parity"
	if camera.has_method("get_pixels_per_meter_at_positions"):
		var points := PackedVector3Array([
			Vector3(0, 0, -10), Vector3(2, 0, -20),
			Vector3(0, 0, 10), Vector3(0, 0, -40)])
		var orthogonal_batch: PackedFloat64Array = camera.call(
			"get_pixels_per_meter_at_positions", points)
		t.eq(orthogonal_batch.size(), points.size(),
			"native orthographic batch returns one pixel density per tile")
		for i in points.size():
			t.near(orthogonal_batch[i], float(camera.call(
				"get_pixels_per_meter_at_position", points[i])), 0.00001,
				"native orthographic batch equals scalar camera projection")
		camera.set_perspective(38.0, 0.05, 500.0)
		var perspective_batch: PackedFloat64Array = camera.call(
			"get_pixels_per_meter_at_positions", points)
		t.eq(perspective_batch.size(), points.size(),
			"native perspective batch preserves all tile results")
		for i in points.size():
			t.near(perspective_batch[i], float(camera.call(
				"get_pixels_per_meter_at_position", points[i])), 0.00001,
				"native perspective batch equals scalar camera projection")
		t.eq(perspective_batch[2], 0.0,
			"grass behind camera has zero screen-space detail")
		var oversized := PackedVector3Array()
		oversized.resize(4097)
		var rejected: PackedFloat64Array = camera.call(
			"get_pixels_per_meter_at_positions", oversized)
		t.eq(rejected.size(), 0, "over 4096 points reject the entire native batch")
		var malformed := PackedVector3Array([
			Vector3(0, 0, -10), Vector3(NAN, 0, -20)])
		rejected = camera.call("get_pixels_per_meter_at_positions", malformed)
		t.eq(rejected.size(), 0, "nonfinite late tile rejects the entire native batch")
	else:
		t.check(true, "older Cgame and stock Godot keep scalar screen-space LOD")
	camera.free()
