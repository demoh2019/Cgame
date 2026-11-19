extends SceneTree
## A moving detached triangle and a pinned target triangle are in ONE
## Jolt soft body. Three moving vertices are kicked toward the target fast
## enough to cross the contact shell within one physics frame.
##
## Control: the same mesh, pinned vertices, materials, and impulses, but
## the target triangle lies 3m away in X: no self contact is possible.
## Gravity, soft-soft inter-body contacts, self EE, XPBD self-position
## recovery and discrete velocity bias are disabled in this scenario.
##
## godot --headless --path tests/stress/jolt_soft_self_vf_sweep \
##   --script res://swept_self_triangle_regression.gd

const PREFIX := "JOLT_SWEPT_SELF_VF_RESULT:"
const FRAMES := 6
const MOVING_VERTICES := 3
const DOWNWARD_IMPULSE := Vector3(0.0, -6.0, 0.0)


func _initialize() -> void:
	call_deferred("_run")


func _mesh(x_origin: float, avoid_self_collision: bool) -> ArrayMesh:
	var offset_target := 3.0 if avoid_self_collision else 0.0
	var vertices := PackedVector3Array([
		# Unpinned source triangle, 0.38m above the target surface.
		Vector3(x_origin - 0.35, 2.38, -0.3),
		Vector3(x_origin + 0.35, 2.38, -0.3),
		Vector3(x_origin, 2.38, 0.4),
		# Disconnected, pinned triangle below the moving piece.
		Vector3(x_origin + offset_target - 1.2, 2.0, -1.1),
		Vector3(x_origin + offset_target + 1.2, 2.0, -1.1),
		Vector3(x_origin + offset_target, 2.0, 1.2),
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 3, 5, 4])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _body(space: RID, mesh: ArrayMesh) -> RID:
	var body := PhysicsServer3D.soft_body_create()
	PhysicsServer3D.soft_body_set_mesh(body, mesh.get_rid())
	PhysicsServer3D.soft_body_set_total_mass(body, 1.2)
	PhysicsServer3D.soft_body_set_linear_stiffness(body, 0.7)
	PhysicsServer3D.soft_body_set_simulation_precision(body, 8)
	PhysicsServer3D.soft_body_set_collision_layer(body, 0)
	PhysicsServer3D.soft_body_set_collision_mask(body, 0)
	PhysicsServer3D.soft_body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	for index in [3, 4, 5]:
		PhysicsServer3D.soft_body_pin_point(body, index, true)
	PhysicsServer3D.soft_body_set_space(body, space)
	return body


func _run() -> void:
	var errors: Array[String] = []
	var config := "physics/jolt_physics_3d/simulation/"
	if str(ProjectSettings.get_setting("physics/3d/physics_engine", "")) != "Jolt Physics":
		errors.append("Jolt backend required")
	for key in ["soft_body_self_contacts", "soft_body_self_speculative_vertex_face_ccd"]:
		if not bool(ProjectSettings.get_setting(config + key, false)):
			errors.append("Missing required mode: " + key)
	for key in ["soft_body_self_edge_contacts", "soft_body_soft_contacts", "soft_body_self_position_projection"]:
		if bool(ProjectSettings.get_setting(config + key, true)):
			errors.append("Confounding feature must be disabled: " + key)
	if float(ProjectSettings.get_setting(config + "soft_body_soft_contact_recovery", -1.0)) != 0.0:
		errors.append("Discrete velocity recovery must be disabled")
	if not errors.is_empty():
		for message in errors:
			printerr(message)
		quit(1)
		return

	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var meshes: Array[ArrayMesh] = [_mesh(0.0, false), _mesh(8.0, true)]
	var bodies: Array[RID] = [_body(space, meshes[0]), _body(space, meshes[1])]
	for warmup in range(2):
		await physics_frame

	var start_hit := PhysicsServer3D.soft_body_get_point_global_position(bodies[0], 0)
	var start_control := PhysicsServer3D.soft_body_get_point_global_position(bodies[1], 0)
	for body in bodies:
		for particle in range(MOVING_VERTICES):
			PhysicsServer3D.soft_body_apply_point_impulse(body, particle, DOWNWARD_IMPULSE)

	var max_hit_fall := 0.0
	var max_control_fall := 0.0
	var started := Time.get_ticks_usec()
	for frame in range(FRAMES):
		await physics_frame
		for body_index in range(bodies.size()):
			var bounds := PhysicsServer3D.soft_body_get_bounds(bodies[body_index])
			if not bounds.position.is_finite() or not bounds.size.is_finite():
				errors.append("Nonfinite bounds at frame " + str(frame))
				break
			for particle in range(6):
				var p := PhysicsServer3D.soft_body_get_point_global_position(bodies[body_index], particle)
				if not p.is_finite():
					errors.append("Nonfinite vertex at frame " + str(frame) + "/" + str(particle))
					break
			if not errors.is_empty():
				break
		if not errors.is_empty():
			break

		var hit_position := PhysicsServer3D.soft_body_get_point_global_position(bodies[0], 0)
		var control_position := PhysicsServer3D.soft_body_get_point_global_position(bodies[1], 0)
		max_hit_fall = maxf(max_hit_fall, start_hit.y - hit_position.y)
		max_control_fall = maxf(max_control_fall, start_control.y - control_position.y)

	if max_control_fall < 0.25:
		errors.append("Control did not move far enough to test fast tunneling")
	if max_hit_fall >= max_control_fall - 0.08:
		errors.append("Speculative self vertex-face contact failed to reduce travel")
	if max_hit_fall > 1.0:
		errors.append("Excessively deep self vertex-face penetration after CCD")

	for body in bodies:
		for index in [3, 4, 5]:
			if not PhysicsServer3D.soft_body_is_point_pinned(body, index):
				errors.append("Target-face pinned vertex released: " + str(index))
		PhysicsServer3D.soft_body_set_space(body, RID())
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"frames": FRAMES,
		"max_ccd_vertex_fall": max_hit_fall,
		"max_control_vertex_fall": max_control_fall,
		"elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"errors": errors
	}))
	if errors.is_empty():
		print("PASS: Jolt swept self vertex-face CCD versus unopposed control")
		quit(0)
	else:
		for message in errors:
			printerr(message)
		quit(1)
