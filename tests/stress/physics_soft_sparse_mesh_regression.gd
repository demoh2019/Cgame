# Integration regression for sparse soft-body structural and bending links.
# Run with a built Godot Physics 3D editor binary:
#   godot --headless --path tests/stress --script res://physics_soft_sparse_mesh_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: Node3D = Node3D.new()
	root.add_child(scene)

	# Thousands of unique physical vertices used to trigger two O(V^2)
	# allocation paths during soft-body mesh initialization.
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 96
	sphere.rings = 64

	var body: SoftBody3D = SoftBody3D.new()
	body.mesh = sphere
	body.simulation_precision = 2
	body.total_mass = 1.0
	body.position = Vector3(0.0, 3.0, 0.0)

	var begin_usec: int = Time.get_ticks_usec()
	scene.add_child(body)
	var mesh_setup_ms: float = float(Time.get_ticks_usec() - begin_usec) / 1000.0

	var failed: bool = false
	var peak_physics_ms: float = 0.0
	for frame in range(20):
		await physics_frame
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		var point: Vector3 = body.get_point_transform(0)
		if not point.is_finite():
			printerr("FAIL: non-finite soft-body vertex after frame %d" % frame)
			failed = true
			break

	scene.queue_free()
	await process_frame

	print("SoftBody3D large-mesh setup_ms=%.3f peak_physics_ms=%.3f" % [mesh_setup_ms, peak_physics_ms])
	if failed:
		printerr("SoftBody3D sparse-link regression failed.")
		quit(1)
	else:
		print("SoftBody3D sparse-link regression passed.")
		quit(0)
