extends Node3D

# Run this benchmark with a real Forward+ rendering device, never --headless.
# For a paired comparison, execute the identical project on the base and patched builds.

const GRID_SIZE := 100
const SPACING := 1.8
const WARMUP_FRAMES := 120
const SAMPLE_FRAMES := 240

var _frames := 0
var _shadow_draw_calls := 0
var _frame_ms := 0.0
var _previous_us := 0

func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.86, 0.88)
	box.material = material

	for x in GRID_SIZE:
		for z in GRID_SIZE:
			var instance := MeshInstance3D.new()
			instance.mesh = box
			instance.position = Vector3((x - GRID_SIZE / 2.0) * SPACING, 0.0, (z - GRID_SIZE / 2.0) * SPACING)
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(instance)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, 25.0, 0.0)
	light.shadow_enabled = true
	add_child(light)

	var camera := Camera3D.new()
	camera.position = Vector3(145.0, 125.0, 145.0)
	camera.far = 700.0
	add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.make_current()
	_previous_us = Time.get_ticks_usec()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var elapsed_ms := (now - _previous_us) / 1000.0
	_previous_us = now
	_frames += 1
	if _frames <= WARMUP_FRAMES:
		return

	_shadow_draw_calls += get_viewport().get_render_info(
		RenderingServer.RENDER_INFO_TYPE_SHADOW,
		RenderingServer.RENDER_INFO_DRAW_CALLS_IN_FRAME
	)
	_frame_ms += elapsed_ms
	if _frames == WARMUP_FRAMES + SAMPLE_FRAMES:
		print("SHADOW_BENCH frames=", SAMPLE_FRAMES,
			" avg_shadow_draw_calls=", float(_shadow_draw_calls) / SAMPLE_FRAMES,
			" avg_frame_ms=", _frame_ms / SAMPLE_FRAMES,
			" renderer=", ProjectSettings.get_setting("rendering/renderer/rendering_method", "default"))
		get_tree().quit()
