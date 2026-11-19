extends SceneTree
## Jolt XPBD must remain finite for the Godot soft-body edge values:
## stiffness 0 disables spring edges and precision 0 clamps to one iteration.

const PREFIX := "JOLT_SOFTBODY_CONSTRAINT_BOUNDS_RESULT:"
const CASES := [
	{"stiffness": 0.0, "precision": 0},
	{"stiffness": 0.0, "precision": -3},
	{"stiffness": 0.000001, "precision": 1},
	{"stiffness": 0.5, "precision": 3},
	{"stiffness": 1.0, "precision": 7}
]
const FRAMES := 5


func _initialize() -> void:
	call_deferred("_exercise")


func _build_mesh() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.5, -0.5, -0.5),
		Vector3(0.5, -0.5, -0.5),
		Vector3(0.0, 0.7, -0.5),
		Vector3(0.0, 0.0, 0.7)
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([
		0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3
	])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _exercise() -> void:
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, 0.0)
	var mesh := _build_mesh()
	var bodies: Array[RID] = []
	var errors: Array[String] = []
	var result_rows: Array[Dictionary] = []

	for i in range(CASES.size()):
		var spec: Dictionary = CASES[i]
		var body := PhysicsServer3D.soft_body_create()
		PhysicsServer3D.soft_body_set_mesh(body, mesh.get_rid())
		PhysicsServer3D.soft_body_set_linear_stiffness(body, float(spec["stiffness"]))
		PhysicsServer3D.soft_body_set_simulation_precision(body, int(spec["precision"]))
		PhysicsServer3D.soft_body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.soft_body_set_collision_layer(body, 1 << i)
		PhysicsServer3D.soft_body_set_collision_mask(body, 0)
		PhysicsServer3D.soft_body_set_space(body, space)
		bodies.append(body)

		var expected_precision := maxi(int(spec["precision"]), 1)
		var actual_precision := PhysicsServer3D.soft_body_get_simulation_precision(body)
		if actual_precision != expected_precision:
			errors.append("Precision mismatch case " + str(i) + ": " + str(actual_precision))

	for frame in range(FRAMES):
		await physics_frame

	for i in range(bodies.size()):
		var body := bodies[i]
		var vertex := PhysicsServer3D.soft_body_get_point_global_position(body, 0)
		var bounds := PhysicsServer3D.soft_body_get_bounds(body)
		if not vertex.is_finite() or not bounds.position.is_finite() or not bounds.size.is_finite():
			errors.append("Nonfinite vertex or bounds in case " + str(i))
		elif bounds.size.length_squared() < 0.0001:
			errors.append("Degenerate bounds in case " + str(i))
		result_rows.append({
			"stiffness": CASES[i]["stiffness"],
			"precision": PhysicsServer3D.soft_body_get_simulation_precision(body),
			"finite": vertex.is_finite() and bounds.position.is_finite() and bounds.size.is_finite()
		})
		PhysicsServer3D.soft_body_set_space(body, RID())
		PhysicsServer3D.free_rid(body)

	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(space)
	print(PREFIX + JSON.stringify({
		"cases": CASES.size(),
		"frames": FRAMES,
		"results": result_rows,
		"errors": errors
	}))
	if errors.is_empty():
		print("Jolt soft-body constraint bounds regression passed.")
		quit(0)
	else:
		for error in errors:
			printerr(error)
		quit(1)
