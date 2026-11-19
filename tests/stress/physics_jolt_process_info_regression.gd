extends SceneTree
## Checks that the native Jolt backend reports actual active bodies and
## contact activity through the common PhysicsServer3D process counters.

const PREFIX := "JOLT_PROCESS_INFO_RESULT:"
const BODY_COUNT := 64
const FRAMES := 12


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var sphere := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(sphere, 0.5)
	var bodies: Array[RID] = []
	var peak_active := 0
	var peak_pairs := 0
	var peak_monitor_pairs := 0

	for i in range(BODY_COUNT):
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(body, sphere)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3(float(i % 8) * 0.85, float(int(i / 8)) * 0.85, 0.0)))
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY,
				Vector3(0.1 if i % 2 == 0 else -0.1, 0.0, 0.0))
		PhysicsServer3D.body_set_space(body, space)
		bodies.append(body)

	for frame in range(FRAMES):
		await physics_frame
		peak_active = maxi(peak_active, PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_ACTIVE_OBJECTS))
		peak_pairs = maxi(peak_pairs, PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_COLLISION_PAIRS))
		peak_monitor_pairs = maxi(peak_monitor_pairs,
				int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))

	for body in bodies:
		PhysicsServer3D.free_rid(body)
	bodies.clear()
	for frame in range(3):
		await physics_frame
	var idle_active := PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_ACTIVE_OBJECTS)
	var idle_pairs := PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_COLLISION_PAIRS)
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(sphere)
	PhysicsServer3D.free_rid(space)

	var failures: Array[String] = []
	if peak_active <= 0 or peak_active > BODY_COUNT:
		failures.append("Active-body count missing or exceeds allocated bodies")
	if peak_pairs <= 0 or peak_monitor_pairs <= 0:
		failures.append("Collision activity counter was zero despite overlapping bodies")
	if idle_active != 0 or idle_pairs != 0:
		failures.append("Physics counters were not reset after the scene became empty")
	print(PREFIX + JSON.stringify({
		"bodies": BODY_COUNT,
		"frames": FRAMES,
		"peak_active": peak_active,
		"peak_contact_manifolds": peak_pairs,
		"peak_monitor_pairs": peak_monitor_pairs,
		"idle_active": idle_active,
		"idle_contact_manifolds": idle_pairs,
		"failures": failures,
	}))
	if failures.is_empty():
		print("Jolt physics process counters regression passed.")
		quit(0)
	else:
		for failure in failures:
			printerr(failure)
		quit(1)
