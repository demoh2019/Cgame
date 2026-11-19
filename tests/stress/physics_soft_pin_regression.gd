# SoftBody3D pinned particle runtime regression for GodotPhysics3D.
# Run: godot --headless --path tests/stress --script res://physics_soft_pin_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)

	var mesh := SphereMesh.new()
	mesh.radius = 0.6
	mesh.height = 1.2
	mesh.radial_segments = 12
	mesh.rings = 8

	# Imported meshes commonly weld duplicated seam/pole vertices into
	# one physics particle. Find two exact visual aliases to test that case.
	var visual_vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var seen := {}
	var first := -1
	var second := -1
	for i in range(visual_vertices.size()):
		var vertex: Vector3 = visual_vertices[i]
		if seen.has(vertex):
			first = int(seen[vertex])
			second = i
			break
		seen[vertex] = i

	if first < 0:
		printerr("FAIL: test mesh contains no welded visual vertex aliases.")
		quit(1)
		return

	var body := SoftBody3D.new()
	body.mesh = mesh
	body.total_mass = 1.0
	body.simulation_precision = 4
	body.position = Vector3(0.0, 3.0, 0.0)
	world.add_child(body)
	for frame in range(4):
		await physics_frame

	var rid: RID = body.get_physics_rid()
	# Create nonzero velocity before pinning, to check that the pin discards it.
	PhysicsServer3D.soft_body_apply_central_impulse(rid, Vector3(0.0, 15.0, 0.0))
	await physics_frame
	PhysicsServer3D.soft_body_pin_point(rid, first, true)
	PhysicsServer3D.soft_body_pin_point(rid, second, true)
	var anchor: Vector3 = PhysicsServer3D.soft_body_get_point_global_position(rid, second)
	var failed := false
	for frame in range(20):
		await physics_frame
		var position: Vector3 = PhysicsServer3D.soft_body_get_point_global_position(rid, second)
		if not position.is_finite() or position.distance_squared_to(anchor) > 0.0001:
			printerr("FAIL: pinned particle drifted in frame ", frame)
			failed = true
			break

	if not failed:
		PhysicsServer3D.soft_body_pin_point(rid, first, false)
		# The other visual alias still pins the same physical node.
		for frame in range(15):
			await physics_frame
			var position: Vector3 = PhysicsServer3D.soft_body_get_point_global_position(rid, second)
			if not position.is_finite() or position.distance_squared_to(anchor) > 0.0001:
				printerr("FAIL: unpinning one alias released a shared pinned particle.")
				failed = true
				break

	if not failed:
		var moved_anchor := anchor + Vector3(0.0, 0.3, 0.0)
		PhysicsServer3D.soft_body_move_point(rid, second, moved_anchor)
		for frame in range(10):
			await physics_frame
			var position: Vector3 = PhysicsServer3D.soft_body_get_point_global_position(rid, second)
			if not position.is_finite() or position.distance_squared_to(moved_anchor) > 0.0001:
				printerr("FAIL: explicitly moved pinned particle did not remain stationary.")
				failed = true
				break

	PhysicsServer3D.soft_body_remove_all_pinned_points(rid)
	world.queue_free()
	await process_frame
	if failed:
		quit(1)
	else:
		print("PASS: pinned SoftBody3D particles preserve kinematic state and welded aliases.")
		quit(0)
