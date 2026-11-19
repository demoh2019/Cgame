extends SceneTree
## Exercise Jolt pending BodyID indexing without flushing to broadphase until
## the end. Randomized (coprime permutation) removals and awake/sleeping
## transitions verify the swap-and-erase index under real RID lifetimes.

const PREFIX := "JOLT_PENDING_INDEX_RESULT:"
const BATCH_SIZE := 512
const WAVES := 24
const PERMUTATION_MULTIPLIER := 73


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, 0.35)
	var initial_mem := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var begin_usec := Time.get_ticks_usec()

	for wave in range(WAVES):
		var bodies: Array[RID] = []
		bodies.resize(BATCH_SIZE)
		for i in range(BATCH_SIZE):
			var body := PhysicsServer3D.body_create()
			PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
			PhysicsServer3D.body_add_shape(body, shape)
			PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
			PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
					Transform3D(Basis(), Vector3(float(i % 32) * 4.0, float(int(i / 32)) * 4.0, 0.0)))
			PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_SLEEPING, i % 2 == 0)
			PhysicsServer3D.body_set_space(body, space)
			bodies[i] = body

		# 73 and 512 are coprime, so every slot is visited exactly once.
		for i in range(BATCH_SIZE):
			var index := (i * PERMUTATION_MULTIPLIER) % BATCH_SIZE
			if i % 3 == 0:
				PhysicsServer3D.body_set_state(
						bodies[index], PhysicsServer3D.BODY_STATE_SLEEPING, i % 2 == 0)
			PhysicsServer3D.free_rid(bodies[index])
		bodies.clear()

	# Reinsert after all pending queues are empty, then advance physics to
	# exercise the reusable index after repeated fully drained batches.
	var survivors: Array[RID] = []
	for i in range(64):
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3(float(i % 8) * 3.0, float(int(i / 8)) * 3.0, 0.0)))
		PhysicsServer3D.body_set_space(body, space)
		survivors.append(body)

	await physics_frame
	var active_count := PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_ACTIVE_OBJECTS)
	var elapsed_ms := float(Time.get_ticks_usec() - begin_usec) / 1000.0
	var memory_after := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	for body in survivors:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(space)

	var result := {
		"waves": WAVES,
		"bodies_per_wave": BATCH_SIZE,
		"removed_before_physics_step": WAVES * BATCH_SIZE,
		"survivors_after_flush": 64,
		"active_after_flush": active_count,
		"duration_ms": elapsed_ms,
		"observed_static_memory_growth_bytes": memory_after - initial_mem,
	}
	print(PREFIX + JSON.stringify(result))
	if active_count <= 0 or active_count > 64:
		printerr("Pending-index churn corrupted the final physics body batch")
		quit(1)
	else:
		print("Jolt pending index churn regression passed.")
		quit(0)
