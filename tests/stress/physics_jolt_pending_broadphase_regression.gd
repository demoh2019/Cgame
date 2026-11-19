extends SceneTree
## When a Jolt body is created and destroyed before its first physics step,
## no broadphase node ever existed for it. Stress that editor/scene-churn path
## with the physics server paused, then verify already-inserted removal still
## works after a normal physics step.

const PREFIX := "JOLT_PENDING_BROADPHASE_RESULT:"
const SINGLE_CHURN := 2048
const BATCH_SIZE := 256
const BATCH_WAVES := 4
const ACTIVE_SURVIVORS := 48


func _initialize() -> void:
	call_deferred("_exercise")


func _new_body(space: RID, shape: RID, index: int) -> RID:
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(), Vector3(float(index % 16) * 2.0,
					float(int(index / 16)) * 2.0, 0.0)))
	PhysicsServer3D.body_set_space(body, space)
	return body


func _exercise() -> void:
	# Stop integration so every body created below remains in Jolt's pending
	# insertion queue until it is removed and destroyed.
	PhysicsServer3D.set_active(false)
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, 0.35)
	var baseline_memory := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var single_start := Time.get_ticks_usec()

	# Each deleted body is the only user-created body in its space. The old
	# implementation rebuilt broadphase on every destruction once the Jolt
	# body count dropped to just the default area.
	for i in range(SINGLE_CHURN):
		var body := _new_body(space, shape, i)
		PhysicsServer3D.free_rid(body)
	var single_churn_ms := float(Time.get_ticks_usec() - single_start) / 1000.0

	var batch_start := Time.get_ticks_usec()
	for wave in range(BATCH_WAVES):
		var bodies: Array[RID] = []
		for i in range(BATCH_SIZE):
			bodies.append(_new_body(space, shape, i))
		for i in range(BATCH_SIZE):
			PhysicsServer3D.free_rid(bodies[(i * 73) % BATCH_SIZE])
		bodies.clear()
	var batch_churn_ms := float(Time.get_ticks_usec() - batch_start) / 1000.0
	var pending_memory := int(Performance.get_monitor(Performance.MEMORY_STATIC))

	# Re-enable stepping and check the opposite path: bodies actually
	# inserted into broadphase still have to be removed normally.
	var survivors: Array[RID] = []
	for i in range(ACTIVE_SURVIVORS):
		survivors.append(_new_body(space, shape, i))
	PhysicsServer3D.set_active(true)
	for frame in range(3):
		await physics_frame
	var active_before_removal := PhysicsServer3D.get_process_info(
			PhysicsServer3D.INFO_ACTIVE_OBJECTS)
	var probe: Transform3D = PhysicsServer3D.body_get_state(
			survivors[0], PhysicsServer3D.BODY_STATE_TRANSFORM)

	PhysicsServer3D.set_active(false)
	for body in survivors:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(space)
	PhysicsServer3D.set_active(true)

	var result := {
		"pending_only_single_deletions": SINGLE_CHURN,
		"pending_only_batch_deletions": BATCH_SIZE * BATCH_WAVES,
		"single_churn_ms": single_churn_ms,
		"batch_churn_ms": batch_churn_ms,
		"active_survivors_before_cleanup": active_before_removal,
		"memory_before_bytes": baseline_memory,
		"memory_after_pending_deletions_bytes": pending_memory,
	}
	print(PREFIX + JSON.stringify(result))
	if active_before_removal <= 0 or active_before_removal > ACTIVE_SURVIVORS or not probe.origin.is_finite():
		printerr("Jolt pending broadphase regression: active-body sanity check failed")
		quit(1)
	else:
		print("Jolt pending broadphase regression passed.")
		quit(0)
