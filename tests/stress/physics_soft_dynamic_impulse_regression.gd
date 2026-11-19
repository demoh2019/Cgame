# Cgame / GodotPhysics3D central impulse normalization regression.
# Run: ./bin/godot.macos.editor.arm64 --headless --path tests/stress \
#     --script res://physics_soft_dynamic_impulse_regression.gd
#
# With no stretch constraints, an impulse applied to half as many dynamic
# particles should give those particles roughly twice the x displacement.
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)

	var sphere := SphereMesh.new()
	sphere.radius = 0.7
	sphere.height = 1.4
	sphere.radial_segments = 12
	sphere.rings = 8

	var vertices: PackedVector3Array = sphere.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var unique_index_by_position := {}
	var unique_indices: Array[int] = []
	for visual_index in range(vertices.size()):
		var position: Vector3 = vertices[visual_index]
		if not unique_index_by_position.has(position):
			unique_index_by_position[position] = visual_index
			unique_indices.append(visual_index)
	if unique_indices.size() < 8:
		printerr("FAIL: expected at least eight unique soft-body particles")
		quit(1)
		return

	var bodies: Array[SoftBody3D] = []
	for i in range(2):
		var body := SoftBody3D.new()
		body.mesh = sphere
		body.total_mass = 1.0
		body.linear_stiffness = 0.0
		body.damping_coefficient = 0.0
		body.drag_coefficient = 0.0
		body.simulation_precision = 1
		body.position = Vector3(-20.0 if i == 0 else 20.0, 8.0, 0.0)
		scene.add_child(body)
		bodies.append(body)

	for frame in range(4):
		await physics_frame

	var fully_dynamic := bodies[0].get_physics_rid()
	var half_pinned := bodies[1].get_physics_rid()
	var pinned_count := unique_indices.size() / 2
	for i in range(pinned_count):
		PhysicsServer3D.soft_body_pin_point(half_pinned, unique_indices[i], true)

	var probe_index: int = unique_indices[unique_indices.size() - 1]
	var before_free := PhysicsServer3D.soft_body_get_point_global_position(fully_dynamic, probe_index)
	var before_pinned := PhysicsServer3D.soft_body_get_point_global_position(half_pinned, probe_index)

	var impulse := Vector3(1.0, 0.0, 0.0)
	PhysicsServer3D.soft_body_apply_central_impulse(fully_dynamic, impulse)
	PhysicsServer3D.soft_body_apply_central_impulse(half_pinned, impulse)
	await physics_frame

	var after_free := PhysicsServer3D.soft_body_get_point_global_position(fully_dynamic, probe_index)
	var after_pinned := PhysicsServer3D.soft_body_get_point_global_position(half_pinned, probe_index)
	var displacement_free := after_free.x - before_free.x
	var displacement_pinned := after_pinned.x - before_pinned.x

	print("SoftBody3D central impulse displacement: all=%.6f half-pinned=%.6f" % [
		displacement_free, displacement_pinned
	])

	var valid := after_free.is_finite() and after_pinned.is_finite()
	# Separate independent particles (stiffness=0) isolate the normalization.
	valid = valid and displacement_free > 0.001
	valid = valid and displacement_pinned > displacement_free * 1.4

	scene.queue_free()
	await process_frame
	if not valid:
		printerr("FAIL: pinned soft-body nodes lost total central impulse")
		quit(1)
	else:
		print("PASS: total central impulse preserved across pinned particles")
		quit(0)
