extends SceneTree
## Repeated Area3D -> SoftBody3D touch/leave cycles must dispatch each
## shape-pair enter/exit exactly once, including duplicate Jolt contacts.

const PREFIX := "JOLT_SOFTBODY_AREA_OVERLAP_RESULT:"
const ROUNDS := 6
const SETTLE_FRAMES := 5

var enters := 0
var exits := 0
var event_errors: Array[String] = []


func _initialize() -> void:
	call_deferred("_exercise")


func _on_area_body_event(status: int, body: RID, instance_id: int, body_shape: int, area_shape: int) -> void:
	if status == PhysicsServer3D.AREA_BODY_ADDED:
		enters += 1
	elif status == PhysicsServer3D.AREA_BODY_REMOVED:
		exits += 1
	else:
		event_errors.append("Unknown area event status: " + str(status))


func _exercise() -> void:
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	# Keep the soft-body tetrahedron near the origin for all rounds.
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, 0.0)

	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5),
		Vector3(0.0, 0.6, -0.5), Vector3(0.0, 0.0, 0.65)
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([
		0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3
	])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var soft_body := PhysicsServer3D.soft_body_create()
	PhysicsServer3D.soft_body_set_mesh(soft_body, mesh.get_rid())
	PhysicsServer3D.soft_body_set_collision_layer(soft_body, 1)
	PhysicsServer3D.soft_body_set_collision_mask(soft_body, 1)
	# Keep contact callbacks flowing even in long idle sensor cycles.
	PhysicsServer3D.soft_body_set_state(soft_body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	PhysicsServer3D.soft_body_set_space(soft_body, space)

	var sensor_shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(sensor_shape, 3.0)
	var area := PhysicsServer3D.area_create()
	PhysicsServer3D.area_add_shape(area, sensor_shape)
	PhysicsServer3D.area_set_collision_layer(area, 1)
	PhysicsServer3D.area_set_collision_mask(area, 1)
	PhysicsServer3D.area_set_monitor_callback(area, Callable(self, "_on_area_body_event"))
	PhysicsServer3D.area_set_transform(area, Transform3D(Basis(), Vector3(50.0, 0.0, 0.0)))
	PhysicsServer3D.area_set_space(area, space)

	var start_usec := Time.get_ticks_usec()
	for cycle in range(ROUNDS):
		PhysicsServer3D.area_set_transform(area, Transform3D(Basis(), Vector3.ZERO))
		for frame in range(SETTLE_FRAMES):
			await physics_frame
		if enters != cycle + 1:
			event_errors.append("enter count after cycle " + str(cycle) + ": " + str(enters))

		PhysicsServer3D.area_set_transform(area, Transform3D(Basis(), Vector3(50.0, 0.0, 0.0)))
		for frame in range(SETTLE_FRAMES):
			await physics_frame
		if exits != cycle + 1:
			event_errors.append("exit count after cycle " + str(cycle) + ": " + str(exits))

	var elapsed_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
	PhysicsServer3D.area_set_monitor_callback(area, Callable())
	PhysicsServer3D.area_set_space(area, RID())
	PhysicsServer3D.soft_body_set_space(soft_body, RID())
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(area)
	PhysicsServer3D.free_rid(soft_body)
	PhysicsServer3D.free_rid(sensor_shape)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"rounds": ROUNDS,
		"settle_frames": SETTLE_FRAMES,
		"enters": enters,
		"exits": exits,
		"elapsed_ms": elapsed_ms,
		"errors": event_errors
	}))
	if event_errors.is_empty() and enters == ROUNDS and exits == ROUNDS:
		print("Jolt soft-body area overlap regression passed.")
		quit(0)
	else:
		for error in event_errors:
			printerr(error)
		quit(1)
