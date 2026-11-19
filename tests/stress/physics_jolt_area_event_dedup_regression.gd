extends SceneTree
## Regression for Jolt's buffered rigid-body / Area3D sensor transitions.
## Eight overlapping area subshapes must report one begin/end each, even
## across persistent contacts and repeated entry/exit waves.

const PREFIX := "JOLT_AREA_EVENT_DEDUP_RESULT:"
const SHAPE_COUNT := 8
const SETTLE_FRAMES := 12
const WAVES := 4

var enters: Array[int] = []
var exits: Array[int] = []
var invalid_events: Array[String] = []


func _initialize() -> void:
	for i in range(SHAPE_COUNT):
		enters.append(0)
		exits.append(0)
	call_deferred("_run")


func _on_event(status: int, body: RID, instance_id: int, body_shape: int, area_shape: int) -> void:
	if area_shape < 0 or area_shape >= SHAPE_COUNT:
		invalid_events.append("Area shape index outside expected range: " + str(area_shape))
		return
	if body_shape != 0:
		invalid_events.append("Unexpected body shape index: " + str(body_shape))
	if status == PhysicsServer3D.AREA_BODY_ADDED:
		enters[area_shape] += 1
	elif status == PhysicsServer3D.AREA_BODY_REMOVED:
		exits[area_shape] += 1
	else:
		invalid_events.append("Unknown event status: " + str(status))


func _assert_counts(expected_entries: int, expected_exits: int, phase: String) -> void:
	for i in range(SHAPE_COUNT):
		if enters[i] != expected_entries or exits[i] != expected_exits:
			invalid_events.append("%s shape %d: expected %d/%d got %d/%d" % [
				phase, i, expected_entries, expected_exits, enters[i], exits[i]
			])


func _run() -> void:
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)

	var area_shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(area_shape, 2.0)
	var body_shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(body_shape, 0.5)

	var area := PhysicsServer3D.area_create()
	for i in range(SHAPE_COUNT):
		PhysicsServer3D.area_add_shape(area, area_shape,
				Transform3D(Basis(), Vector3((float(i) - 3.5) * 0.20, 0.0, 0.0)))
	PhysicsServer3D.area_set_collision_layer(area, 1)
	PhysicsServer3D.area_set_collision_mask(area, 1)
	PhysicsServer3D.area_set_monitor_callback(area, Callable(self, "_on_event"))
	PhysicsServer3D.area_set_space(area, space)

	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_add_shape(body, body_shape)
	PhysicsServer3D.body_set_collision_layer(body, 1)
	PhysicsServer3D.body_set_collision_mask(body, 1)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(), Vector3(0.0, 20.0, 0.0)))
	PhysicsServer3D.body_set_space(body, space)

	var started := Time.get_ticks_usec()
	for wave in range(WAVES):
		# The first phase establishes eight independent overlaps; holding
		# them over several physics steps must not create duplicate enters.
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3.ZERO))
		for frame in range(SETTLE_FRAMES):
			await physics_frame
		_assert_counts(wave + 1, wave, "entered")

		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3(0.0, 20.0, 0.0)))
		for frame in range(SETTLE_FRAMES):
			await physics_frame
		_assert_counts(wave + 1, wave + 1, "exited")

	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	PhysicsServer3D.area_set_monitor_callback(area, Callable())
	PhysicsServer3D.area_set_space(area, RID())
	PhysicsServer3D.body_set_space(body, RID())
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(area)
	PhysicsServer3D.free_rid(body_shape)
	PhysicsServer3D.free_rid(area_shape)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"waves": WAVES,
		"area_subshapes": SHAPE_COUNT,
		"frames_per_phase": SETTLE_FRAMES,
		"total_enters": enters,
		"total_exits": exits,
		"elapsed_ms": elapsed_ms,
		"failures": invalid_events
	}))
	if invalid_events.is_empty():
		print("Jolt rigid Area3D event dedup regression passed.")
		quit(0)
	else:
		for error in invalid_events:
			printerr(error)
		quit(1)
