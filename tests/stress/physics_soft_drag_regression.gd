# GodotPhysics3D aerodynamic drag integration regression.
# Run with a built editor binary:
#   ./bin/godot.macos.editor.arm64 --headless --path tests/stress \
#      --script res://physics_soft_drag_regression.gd
# Compares matched soft spheres with and without drag.
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)

	var bodies: Array[SoftBody3D] = []
	for i in range(2):
		var sphere := SphereMesh.new()
		sphere.radius = 0.65
		sphere.height = 1.3
		sphere.radial_segments = 12
		sphere.rings = 8

		var body := SoftBody3D.new()
		body.mesh = sphere
		body.total_mass = 1.0
		body.simulation_precision = 4
		body.damping_coefficient = 0.0
		body.drag_coefficient = 0.0 if i == 0 else 0.9
		body.position = Vector3(-12.0 if i == 0 else 12.0, 8.0, 0.0)
		world.add_child(body)
		bodies.append(body)

	for frame in range(5):
		await physics_frame

	var starts: Array[Vector3] = [
		bodies[0].get_point_transform(0),
		bodies[1].get_point_transform(0),
	]
	for body in bodies:
		PhysicsServer3D.soft_body_apply_central_impulse(
			body.get_physics_rid(), Vector3(5.0, 0.0, 0.0)
		)

	var finite := true
	for frame in range(90):
		await physics_frame
		for body in bodies:
			if not body.get_point_transform(0).is_finite():
				printerr("FAIL: aerodynamic drag produced non-finite soft-body point")
				finite = false
				break
		if not finite:
			break

	var no_drag_x := bodies[0].get_point_transform(0).x - starts[0].x
	var drag_x := bodies[1].get_point_transform(0).x - starts[1].x
	print("SoftBody3D aerodynamic drag displacement: zero=%.4f drag=%.4f" % [no_drag_x, drag_x])

	world.queue_free()
	await process_frame

	if not finite or no_drag_x < 0.2 or drag_x >= no_drag_x - 0.05:
		printerr("FAIL: enabled soft-body drag should dissipate horizontal motion")
		quit(1)
	else:
		print("PASS: soft-body drag dissipates motion without non-finite points")
		quit(0)
