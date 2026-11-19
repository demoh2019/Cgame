extends SceneTree
## Runtime stress for repeated Jolt pending-body batch submission and cleanup.
## Works with the engine's selected 3D backend; run with Jolt for targeted coverage.

const PREFIX := "PHYSICS_PENDING_REUSE_RESULT:"
const COUNT := 512
const ROUNDS := 32

func _initialize() -> void:
	call_deferred("_exercise")


func _exercise() -> void:
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, 0.35)
	var baseline_memory := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var peak_memory := baseline_memory
	var peak_physics_ms := 0.0
	var start_usec := Time.get_ticks_usec()

	for cycle in range(ROUNDS):
		var bodies: Array[RID] = []
		bodies.resize(COUNT)
		for i in range(COUNT):
			var body := PhysicsServer3D.body_create()
			PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
			PhysicsServer3D.body_add_shape(body, shape)
			PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
					Transform3D(Basis(), Vector3(float(i % 64) * 4.0, float(int(i / 64)) * 4.0, 0.0)))
			PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
			PhysicsServer3D.body_set_space(body, space)
			bodies[i] = body
		# Force Jolt's pending awake queue to flush once for every batch.
		await physics_frame
		peak_physics_ms = maxf(peak_physics_ms,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		peak_memory = maxi(peak_memory, int(Performance.get_monitor(Performance.MEMORY_STATIC)))
		for body in bodies:
			PhysicsServer3D.free_rid(body)
		bodies.clear()
		await physics_frame

	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(space)
	var result := {
		"rounds": ROUNDS,
		"bodies_per_round": COUNT,
		"total_body_creations": ROUNDS * COUNT,
		"peak_physics_ms": peak_physics_ms,
		"elapsed_ms": float(Time.get_ticks_usec() - start_usec) / 1000.0,
		"observed_static_memory_growth_bytes": peak_memory - baseline_memory,
	}
	print(PREFIX + JSON.stringify(result))
	quit(0)
