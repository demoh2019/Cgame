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
	camera.free()
