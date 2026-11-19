extends SceneTree
## Dense reported-contact burst followed by a quiet scene. The contact listener
## must release oversized temporary storage without losing any contact events.

const RESULT_PREFIX := "JOLT_CONTACT_SCRATCH_RESULT:"
const BODY_COUNT := 4096
const KEEP_COUNT := 64
const DENSE_FRAMES := 4
const QUIET_FRAMES := 4

func _initialize() -> void:
	call_deferred("_exercise")


func _exercise() -> void:
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, 0.5)
	var bodies: Array[RID] = []
	bodies.resize(BODY_COUNT)
	var side := 16
	var started := Time.get_ticks_usec()
	var initial_memory := int(Performance.get_monitor(Performance.MEMORY_STATIC))

	for i in range(BODY_COUNT):
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_max_contacts_reported(body, 4)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3(float(i % side) * 0.85,
						float(int(i / side) % side) * 0.85,
						float(int(i / (side * side))) * 0.85)))
		PhysicsServer3D.body_set_space(body, space)
		bodies[i] = body

	var peak_pairs := 0
	var peak_physics_ms := 0.0
	for frame in range(DENSE_FRAMES):
		await physics_frame
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
		peak_physics_ms = maxf(peak_physics_ms,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	var dense_memory := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var dense_ms := float(Time.get_ticks_usec() - started) / 1000.0

	# Drop from thousands of reporting bodies to just a tiny isolated group.
	for i in range(KEEP_COUNT, BODY_COUNT):
		PhysicsServer3D.free_rid(bodies[i])
	for frame in range(QUIET_FRAMES):
		await physics_frame
	var quiet_memory := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var quiet_transform: Transform3D = PhysicsServer3D.body_get_state(
			bodies[0], PhysicsServer3D.BODY_STATE_TRANSFORM)

	for i in range(KEEP_COUNT):
		PhysicsServer3D.free_rid(bodies[i])
	bodies.clear()
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(space)

	var result := {
		"bodies_created": BODY_COUNT,
		"bodies_retained_after_burst": KEEP_COUNT,
		"reported_contacts_per_body": 4,
		"peak_collision_pairs": peak_pairs,
		"peak_physics_ms": peak_physics_ms,
		"dense_ms": dense_ms,
		"initial_static_memory_bytes": initial_memory,
		"dense_static_memory_bytes": dense_memory,
		"quiet_static_memory_bytes": quiet_memory,
	}
	print(RESULT_PREFIX + JSON.stringify(result))
	if peak_pairs <= 0 or not quiet_transform.origin.is_finite():
		printerr("Jolt reported-contact burst was missing contacts or became non-finite")
		quit(1)
	else:
		quit(0)
