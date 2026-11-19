extends SceneTree
## Persistent Jolt self-edge BVH: refit for 120 frames, rebuild, then
## destroy/recreate an active soft body to prove stale cache eviction.
## Two perpendicularly crossing 8x8
## panels are inside ONE soft body; 196 faces and >300 edges guarantee
## the BVH's eligible mesh-size path. Adjacent control is an uncreased
## 8x8 sheet located away from the interacting panels.
##
## Run: --headless --path tests/stress/jolt_soft_self_edge_bvh --script res://bvh_self_edges_regression.gd

const PREFIX := "JOLT_SELF_EDGE_BVH_RESULT:"
const GRID := 8
const FRAMES := 152
const RECREATE_FRAME := 128


func _initialize() -> void:
	call_deferred("_run")


func _mesh(verts: PackedVector3Array, triangles: PackedInt32Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = triangles
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _panels(crossing: bool, offset_x: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	var count := 2 if crossing else 1
	for panel in range(count):
		var start := verts.size()
		for z in range(GRID):
			for x in range(GRID):
				var fx := -1.0 + 2.0 * x / (GRID - 1)
				var fz := -1.0 + 2.0 * z / (GRID - 1)
				if panel == 1:
					# Vertical Y/Z sheet at x=offset_x+0.04.
					verts.append(Vector3(offset_x + 0.04, 2.0 + fz, fx))
				else:
					verts.append(Vector3(offset_x + fx, 2.0, fz))
		for z in range(GRID - 1):
			for x in range(GRID - 1):
				var a := start + z * GRID + x
				var b := a + 1
				var c := a + GRID
				var d := c + 1
				indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	return _mesh(verts, indices)


func _body(space: RID, mesh: ArrayMesh, panels: int) -> RID:
	var rid := PhysicsServer3D.soft_body_create()
	PhysicsServer3D.soft_body_set_mesh(rid, mesh.get_rid())
	PhysicsServer3D.soft_body_set_total_mass(rid, 2.0)
	PhysicsServer3D.soft_body_set_linear_stiffness(rid, 0.7)
	PhysicsServer3D.soft_body_set_simulation_precision(rid, 10)
	PhysicsServer3D.soft_body_set_collision_layer(rid, 0)
	PhysicsServer3D.soft_body_set_collision_mask(rid, 0)
	PhysicsServer3D.soft_body_set_state(rid, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	for panel in range(panels):
		for corner in [0, GRID - 1, GRID * (GRID - 1), GRID * GRID - 1]:
			PhysicsServer3D.soft_body_pin_point(rid, panel * GRID * GRID + corner, true)
	PhysicsServer3D.soft_body_set_space(rid, space)
	return rid


func _run() -> void:
	var errors: Array[String] = []
	var root := "physics/jolt_physics_3d/simulation/"
	if str(ProjectSettings.get_setting("physics/3d/physics_engine", "")) != "Jolt Physics":
		errors.append("Expected Jolt physics backend")
	for key in ["soft_body_self_contacts", "soft_body_self_edge_contacts", "soft_body_self_edge_bvh"]:
		if not bool(ProjectSettings.get_setting(root + key, false)):
			errors.append("Required experimental physics mode not enabled: " + key)
	if not errors.is_empty():
		for err in errors:
			printerr(err)
		quit(1)
		return

	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var meshes: Array[ArrayMesh] = [_panels(true, 0.0), _panels(false, 6.0)]
	var bodies: Array[RID] = [
		_body(space, meshes[0], 2),
		_body(space, meshes[1], 1)
	]
	for frame in range(2):
		await physics_frame

	var center_start := PhysicsServer3D.soft_body_get_point_global_position(bodies[0], GRID * 4 + 4)
	var control_start := PhysicsServer3D.soft_body_get_point_global_position(bodies[1], GRID * 4 + 4)
	var maximum_motion := 0.0
	var maximum_control_drift := 0.0
	var start_usec := Time.get_ticks_usec()

	for frame in range(FRAMES):
		await physics_frame
		if frame == RECREATE_FRAME:
			# Must evict the old BodyID's topology/BVH cache. This also
			# verifies a replacement with the same mesh doesn't use stale
			# leaf mappings or live particle pointers.
			PhysicsServer3D.soft_body_set_space(bodies[0], RID())
			PhysicsServer3D.free_rid(bodies[0])
			bodies[0] = _body(space, meshes[0], 2)
			await physics_frame
			center_start = PhysicsServer3D.soft_body_get_point_global_position(bodies[0], GRID * 4 + 4)
		for body_idx in range(bodies.size()):
			var bounds := PhysicsServer3D.soft_body_get_bounds(bodies[body_idx])
			if not bounds.position.is_finite() or not bounds.size.is_finite():
				errors.append("Nonfinite bounds, body " + str(body_idx) + " frame " + str(frame))
				break
			var particle_count := (2 if body_idx == 0 else 1) * GRID * GRID
			for i in range(particle_count):
				var p := PhysicsServer3D.soft_body_get_point_global_position(bodies[body_idx], i)
				if not p.is_finite():
					errors.append("Nonfinite particle, body " + str(body_idx) + " frame " + str(frame))
					break
			if not errors.is_empty():
				break
		if not errors.is_empty():
			break
		var center_now := PhysicsServer3D.soft_body_get_point_global_position(bodies[0], GRID * 4 + 4)
		var control_now := PhysicsServer3D.soft_body_get_point_global_position(bodies[1], GRID * 4 + 4)
		maximum_motion = maxf(maximum_motion, center_start.distance_to(center_now))
		maximum_control_drift = maxf(maximum_control_drift, control_start.distance_to(control_now))

	if maximum_motion > 10.0:
		errors.append("Unstable large self-collision displacement")
	if maximum_control_drift > 0.08:
		errors.append("Adjacent control cloth exhibited unexpected motion")
	for body_idx in range(bodies.size()):
		for panel in range(2 if body_idx == 0 else 1):
			for corner in [0, GRID - 1, GRID * (GRID - 1), GRID * GRID - 1]:
				var index := panel * GRID * GRID + corner
				if not PhysicsServer3D.soft_body_is_point_pinned(bodies[body_idx], index):
					errors.append("Pinned corner lost: " + str(body_idx) + "/" + str(index))

	for rid in bodies:
		PhysicsServer3D.soft_body_set_space(rid, RID())
		PhysicsServer3D.free_rid(rid)
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"panels": 2,
		"self_body_faces": 4 * (GRID - 1) * (GRID - 1),
		"frames": FRAMES,
		"recreate_frame": RECREATE_FRAME,
		"maximum_center_motion": maximum_motion,
		"maximum_adjacent_control_drift": maximum_control_drift,
		"elapsed_ms": float(Time.get_ticks_usec() - start_usec) / 1000.0,
		"errors": errors
	}))
	if errors.is_empty():
		print("PASS: Jolt persistent self-edge BVH refit and body recreation")
		quit(0)
	else:
		for error in errors:
			printerr(error)
		quit(1)
