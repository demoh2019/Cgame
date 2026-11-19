extends SceneTree
## Jolt XPBD dihedral bending + aerodynamic drag on a closed soft tetrahedron.
## Run from this directory's Jolt-enabled project.godot, not tests/stress.
##
##   ./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
##       --path tests/stress/jolt_physics \
##       --script res://softbody_aerodynamics_regression.gd

const PREFIX := "JOLT_SOFTBODY_AERODYNAMICS_RESULT:"
const DRAGS := [0.0, 1.5, 1000.0, 0.0, 1.5]
const IMPULSE := 5.0
const FRAMES := 90

func _initialize() -> void:
	call_deferred("_run")


func _create_mesh() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.6, -0.6, -0.6),
		Vector3(0.6, -0.6, -0.6),
		Vector3(0.0, 0.7, -0.6),
		Vector3(0.0, 0.0, 0.8),
	])
	# Closed tetrahedron; each face has outward consistent winding.
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([
		0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3
	])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _run() -> void:
	var errors: Array[String] = []
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, 0.0)
	var mesh := _create_mesh()
	var bodies: Array[RID] = []

	if str(ProjectSettings.get_setting("physics/3d/physics_engine")) != "Jolt Physics":
		errors.append("Fixture must use the Jolt Physics backend")
	if int(ProjectSettings.get_setting("physics/jolt_physics_3d/simulation/soft_body_bend_mode")) != 2:
		errors.append("Fixture must enable dihedral XPBD bending")

	for i in range(DRAGS.size()):
		var body := PhysicsServer3D.soft_body_create()
		PhysicsServer3D.soft_body_set_mesh(body, mesh.get_rid())
		PhysicsServer3D.soft_body_set_total_mass(body, 1.0)
		PhysicsServer3D.soft_body_set_linear_stiffness(body, 0.7)
		PhysicsServer3D.soft_body_set_simulation_precision(body, 7)
		PhysicsServer3D.soft_body_set_damping_coefficient(body, 0.0)
		PhysicsServer3D.soft_body_set_drag_coefficient(body, DRAGS[i])
		PhysicsServer3D.soft_body_set_collision_layer(body, 1 << i)
		PhysicsServer3D.soft_body_set_collision_mask(body, 0)
		PhysicsServer3D.soft_body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.soft_body_set_space(body, space)
		var returned_drag := PhysicsServer3D.soft_body_get_drag_coefficient(body)
		if absf(returned_drag - DRAGS[i]) > 0.0001:
			errors.append("Drag setter/getter mismatch at body " + str(i))
		bodies.append(body)

	for frame in range(5):
		await physics_frame

	var starts: Array[float] = []
	for body in bodies:
		starts.append(PhysicsServer3D.soft_body_get_point_global_position(body, 0).x)

	var started_usec := Time.get_ticks_usec()
	for i in range(bodies.size()):
		var sign := 1.0 if i < 3 else -1.0
		PhysicsServer3D.soft_body_apply_central_impulse(bodies[i], Vector3(sign * IMPULSE, 0.0, 0.0))

	for frame in range(FRAMES):
		await physics_frame
		if frame % 5 != 0 and frame != FRAMES - 1:
			continue
		for i in range(bodies.size()):
			var bounds := PhysicsServer3D.soft_body_get_bounds(bodies[i])
			if not bounds.position.is_finite() or not bounds.size.is_finite():
				errors.append("Nonfinite bounds: body " + str(i) + ", frame " + str(frame))
			for vertex in range(4):
				var position := PhysicsServer3D.soft_body_get_point_global_position(bodies[i], vertex)
				if not position.is_finite():
					errors.append("Nonfinite vertex: body " + str(i) + ", frame " + str(frame))

	var distances: Array[float] = []
	for i in range(bodies.size()):
		var point := PhysicsServer3D.soft_body_get_point_global_position(bodies[i], 0)
		distances.append(absf(point.x - starts[i]))

	if distances[0] < 0.3 or distances[3] < 0.3:
		errors.append("Impulse did not move the undamped reference")
	if distances[1] >= distances[0] - 0.1:
		errors.append("Positive-direction drag did not reduce displacement")
	if distances[2] >= distances[0] - 0.1:
		errors.append("Extreme drag did not reduce displacement")
	if distances[4] >= distances[3] - 0.1:
		errors.append("Negative-direction drag did not reduce displacement")

	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.soft_body_set_space(body, RID())
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"frames": FRAMES,
		"drag_values": DRAGS,
		"displacements": distances,
		"bend_mode": ProjectSettings.get_setting("physics/jolt_physics_3d/simulation/soft_body_bend_mode"),
		"elapsed_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
		"errors": errors,
	}))
	if errors.is_empty():
		print("Jolt aerodynamic drag + dihedral bend regression passed.")
		quit(0)
	else:
		for failure in errors:
			printerr(failure)
		quit(1)
