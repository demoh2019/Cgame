# Built-in GodotPhysics3D SoftBody3D segment raycast integration test.
# Run: ./bin/godot.macos.editor.arm64 --headless --path tests/stress \
#   --script res://physics_soft_segment_raycast_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _cast(space_state: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, back_faces: bool = false) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.hit_back_faces = back_faces
	query.collision_mask = 1
	return space_state.intersect_ray(query)


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)

	# Two upward-facing triangles at y=0 and y=-0.5.
	# Their independent visual vertices also give distinct physics face IDs.
	var vertices := PackedVector3Array([
		Vector3(-1.0, 0.0, -1.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(1.0, 0.0, -1.0),
		Vector3(-1.0, -0.5, -1.0),
		Vector3(0.0, -0.5, 1.0),
		Vector3(1.0, -0.5, -1.0),
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 3, 4, 5])

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var body := SoftBody3D.new()
	body.mesh = mesh
	body.total_mass = 1.0
	body.collision_layer = 1
	body.collision_mask = 1
	world.add_child(body)

	# Prevent any gravity/deformation from moving test triangles between rays.
	for i in range(vertices.size()):
		PhysicsServer3D.soft_body_pin_point(body.get_physics_rid(), i, true)

	for frame in range(3):
		await physics_frame

	var state := world.get_world_3d().direct_space_state
	var failed := false

	var front := _cast(state, Vector3(0.0, 1.0, 0.0), Vector3(0.0, -1.0, 0.0))
	if front.is_empty() or int(front.get("face_index", -1)) != 0:
		printerr("FAIL: expected nearest upper soft-body triangle (face 0).")
		failed = true
	elif front["normal"].y < 0.9 or absf(front["position"].y) > 0.001:
		printerr("FAIL: front-face normal/position is incorrect.")
		failed = true

	# The short ray stops inside the inflated BVH AABB but before the face.
	var clipped := _cast(state, Vector3(0.0, 0.07, 0.0), Vector3(0.0, 0.025, 0.0))
	if not clipped.is_empty():
		printerr("FAIL: soft-body ray escaped the finite segment.")
		failed = true

	var back := _cast(state, Vector3(0.0, -0.25, 0.0), Vector3(0.0, 0.5, 0.0))
	if not back.is_empty():
		printerr("FAIL: back face was hit when disabled.")
		failed = true

	var back_enabled := PhysicsRayQueryParameters3D.create(Vector3(0.0, -0.25, 0.0), Vector3(0.0, 0.5, 0.0))
	back_enabled.hit_back_faces = true
	var reversed_hit := state.intersect_ray(back_enabled)
	if reversed_hit.is_empty() or int(reversed_hit.get("face_index", -1)) != 0:
		printerr("FAIL: back-face hit did not return the right triangle.")
		failed = true
	elif reversed_hit["normal"].y > -0.9:
		printerr("FAIL: back-face normal must point against the cast.")
		failed = true

	var long_ray := _cast(state, Vector3(0.0, 1e8, 0.0), Vector3(0.0, -1e8, 0.0))
	if long_ray.is_empty() or int(long_ray.get("face_index", -1)) != 0:
		printerr("FAIL: long soft-body ray should hit the nearest face.")
		failed = true

	world.queue_free()
	await process_frame
	if failed:
		quit(1)
	else:
		print("PASS: SoftBody3D finite raycasts, back faces, normals and face indices.")
		quit(0)
