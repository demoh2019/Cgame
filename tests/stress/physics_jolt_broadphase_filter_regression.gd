extends SceneTree
## Verify Jolt's broadphase classification of monitorable and
## nonmonitorable Area3D sensors against dynamic bodies. This complements
## the existing static/dynamic object-layer collision-mask test.

const PREFIX := "JOLT_BROADPHASE_FILTER_RESULT:"
const FRAMES := 12

var entered: Array[int] = [0, 0]
var exited: Array[int] = [0, 0]


func _initialize() -> void:
	call_deferred("_run")


func _on_area_event(status: int, body: RID, instance_id: int, body_shape: int, area_shape: int, index: int) -> void:
	if status == PhysicsServer3D.AREA_BODY_ADDED:
		entered[index] += 1
	elif status == PhysicsServer3D.AREA_BODY_REMOVED:
		exited[index] += 1


func _run() -> void:
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var sensor_shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(sensor_shape, 2.0)
	var body_shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(body_shape, 0.5)

	var areas: Array[RID] = []
	var bodies: Array[RID] = []
	for i in range(2):
		var position := Vector3(float(i) * 8.0, 0.0, 0.0)
		var area := PhysicsServer3D.area_create()
		PhysicsServer3D.area_add_shape(area, sensor_shape)
		PhysicsServer3D.area_set_collision_layer(area, 1 << i)
		PhysicsServer3D.area_set_collision_mask(area, 1 << i)
		# Classify the same sensor behavior in both Jolt broadphase trees:
		# AREA_DETECTABLE and AREA_UNDETECTABLE.
		PhysicsServer3D.area_set_monitorable(area, i == 0)
		PhysicsServer3D.area_set_monitor_callback(area, Callable(self, "_on_area_event").bind(i))
		PhysicsServer3D.area_set_transform(area, Transform3D(Basis(), position))
		PhysicsServer3D.area_set_space(area, space)
		areas.append(area)

		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(body, body_shape)
		PhysicsServer3D.body_set_collision_layer(body, 1 << i)
		PhysicsServer3D.body_set_collision_mask(body, 1 << i)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), position))
		PhysicsServer3D.body_set_space(body, space)
		bodies.append(body)

	for frame in range(FRAMES):
		await physics_frame

	var initial_entries := entered.duplicate()
	var errors: Array[String] = []
	for i in range(2):
		if entered[i] != 1 or exited[i] != 0:
			errors.append("Expected exactly one enter for area " + str(i) +
					", got " + str(entered[i]) + "/" + str(exited[i]))

	for i in range(2):
		PhysicsServer3D.body_set_state(bodies[i], PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3(float(i) * 8.0, 20.0, 0.0)))

	for frame in range(FRAMES):
		await physics_frame

	for i in range(2):
		if entered[i] != 1 or exited[i] != 1:
			errors.append("Expected one enter/exit for area " + str(i) +
					", got " + str(entered[i]) + "/" + str(exited[i]))

	for area in areas:
		PhysicsServer3D.area_set_monitor_callback(area, Callable())
		PhysicsServer3D.area_set_space(area, RID())
	for body in bodies:
		PhysicsServer3D.body_set_space(body, RID())
	PhysicsServer3D.space_set_active(space, false)
	for area in areas:
		PhysicsServer3D.free_rid(area)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(sensor_shape)
	PhysicsServer3D.free_rid(body_shape)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"frames_per_phase": FRAMES,
		"monitorable_area_enters": initial_entries[0],
		"unmonitorable_area_enters": initial_entries[1],
		"final_enters": entered,
		"final_exits": exited,
		"errors": errors,
	}))
	if errors.is_empty():
		print("Jolt broadphase filter regression passed.")
		quit(0)
	else:
		for error in errors:
			printerr(error)
		quit(1)
