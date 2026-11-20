extends RefCounted
## Pixel-stable GPU atmosphere: no additional draws, VRAM textures or
## CPU-per-particle loops. Native fork and regular Godot fallback agree.
const MoteScreenSpace = preload("res://scripts/client/mote_screen_space.gd")
const AmbientMotes = preload("res://scripts/client/ambient_motes.gd")


func run(t) -> void:
	t.current = "cinematic particle pixel budget"
	t.eq(MoteScreenSpace.target_pixels(0), 0.0, "Performance does not spawn atmospheric motes")
	t.check(MoteScreenSpace.target_pixels(1) < MoteScreenSpace.target_pixels(2),
		"High uses more visible but bounded light points")
	t.check(MoteScreenSpace.target_pixels(2) < MoteScreenSpace.target_pixels(3),
		"Ultra gives the brightest fireflies enough pixel coverage")
	t.check(MoteScreenSpace.target_pixels(1, 0.5) >= 3.5,
		"FSR2 half-resolution retains at least 1.75 internal pixels")
	t.eq(MoteScreenSpace.target_pixels(1, NAN), 3.0,
		"invalid dynamic scaling falls back to a safe full-resolution footprint")
	t.eq(MoteScreenSpace.target_pixels(-5), 0.0,
		"negative quality clamps to Performance")
	t.eq(MoteScreenSpace.target_pixels(99), 4.0,
		"quality beyond Ultra cannot cause unbounded overdraw")

	t.current = "native camera projection and fallback geometry"
	var viewport := Vector2(400.0, 200.0)
	t.near(MoteScreenSpace.fallback_world_diameter(2.0, viewport,
		90.0, 20.0, false, false, 10.0), 0.2, 0.0001,
		"90 degree perspective maps two pixels to 0.2 meters at 10m")
	t.near(MoteScreenSpace.fallback_world_diameter(2.0, viewport,
		90.0, 20.0, true, false, 10.0), 0.1, 0.0001,
		"KEEP_WIDTH camera uses horizontal pixel density")
	t.near(MoteScreenSpace.fallback_world_diameter(2.0, viewport,
		90.0, 20.0, false, false, 20.0), 0.4, 0.0001,
		"feature world size doubles at twice the camera depth")
	t.near(MoteScreenSpace.fallback_world_diameter(2.0, viewport,
		90.0, 20.0, false, true, 10.0), 0.2, 0.0001,
		"orthographic sizing uses camera height")
	t.near(MoteScreenSpace.fallback_world_diameter(2.0, viewport,
		90.0, 20.0, false, true, 100.0), 0.2, 0.0001,
		"orthographic motes never grow with distance")
	t.eq(MoteScreenSpace.fallback_world_diameter(2.0, Vector2.ZERO,
		90.0, 20.0, false, false, 10.0), 0.0,
		"zero-height viewport cannot create infinite quads")
	t.eq(MoteScreenSpace.fallback_world_diameter(2.0, viewport,
		90.0, 20.0, false, false, -1.0), 0.0,
		"camera-behind reference point cannot explode geometry")
	t.eq(MoteScreenSpace.safe_diameter(500.0), MoteScreenSpace.MAX_WORLD_DIAMETER,
		"far extreme is capped to avoid large additive bloom cards")
	t.eq(MoteScreenSpace.safe_diameter(0.0001), MoteScreenSpace.MIN_WORLD_DIAMETER,
		"near extreme retains a nonzero stable feature")

	t.current = "live atmosphere keeps one GPU batch"
	var visual_source: String = (AmbientMotes as Script).source_code
	t.check(visual_source.contains('get_world_size_for_pixel_diameter_at_position'),
		"existing atmospheric renderer uses native engine camera sizing")
	t.check(visual_source.contains('MoteScreenSpace.fallback_world_diameter('),
		"ordinary Godot retains fallback behavior")
	t.check(visual_source.contains('func _update_screen_pixel_size('),
		"camera quality updates only at existing 4 Hz cadence")
	t.check(visual_source.contains('_batch.visible_instance_count'),
		"screen-space sizing does not replace existing GPU MultiMesh")
	var shader: Shader = load("res://assets/shaders/ambient_motes.gdshader") as Shader
	t.check(shader != null, "mote shader resource remains loadable")
	if shader != null:
		var code: String = shader.code
		t.check(code.contains("mote_world_size_at_reference")
			and code.contains("mote_reference_depth"),
			"all motes share one analytic pixel-size calibration")
		t.check(code.contains("mote_orthographic ? 1.0"),
			"orthographic camera keeps fixed world size")
		t.check(code.contains("world_diameter = clamp("),
			"vertex shader bounds world-space billboard size")
		t.check(code.contains("VIEW_MATRIX") and code.contains("INV_VIEW_MATRIX"),
			"existing camera-facing quad transform remains intact")
