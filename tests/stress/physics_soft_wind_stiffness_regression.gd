# Regression for built-in GodotPhysics3D soft-body wind and live parameters.
# Run:
#   ./bin/godot.macos.editor.arm64 --headless --path tests/stress \
#       --script res://physics_soft_wind_stiffness_regression.gd
# This test must use the GodotPhysics3D backend, not Jolt.
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)

	var wind_area := Area3D.new()
	wind_area.name = "WindArea"
	wind_area.collision_layer = 1
	wind_area.collision_mask = 1
	wind_area.wind_force_magnitude = 9.0
	wind_area.wind_attenuation_factor = 0.5

	var wind_source := Node3D.new()
	wind_source.name = "WindSource"
	wind_area.add_child(wind_source)

	var region := CollisionShape3D.new()
	var region_shape := BoxShape3D.new()
	region_shape.size = Vector3(30.0, 30.0, 30.0)
	region.shape = region_shape
	wind_area.add_child(region)
	scene.add_child(wind_area)
	wind_area.wind_source_path = NodePath("WindSource")

	# The default wind direction is local -Z. A mesh at positive Z had a
	# negative signed wind projection, previously invalid for pow(x, -0.5).
	var sphere := SphereMesh.new()
	sphere.radial_segments = 12
	sphere.rings = 8
	var body := SoftBody3D.new()
	body.mesh = sphere
	body.position = Vector3(0.0, 1.5, 4.0)
	body.total_mass = 1.0
	body.linear_stiffness = 0.0
	scene.add_child(body)

	var failed := false
	for frame in range(70):
		await physics_frame
		# Exercise parameter changes after deformation, not just initialization.
		if frame == 18:
			body.linear_stiffness = 0.8
			body.total_mass = 2.0
		if frame == 38:
			# Default, unattenuated wind should take the fast path.
			wind_area.wind_attenuation_factor = 0.0

		var position: Vector3 = body.get_point_transform(0)
		if not position.is_finite():
			printerr("FAIL: SoftBody3D wind/stiffness generated non-finite vertex at frame ", frame)
			failed = true
			break

	scene.queue_free()
	await process_frame
	if failed:
		quit(1)
	else:
		print("PASS: SoftBody3D wind and live material parameters remain finite.")
		quit(0)
