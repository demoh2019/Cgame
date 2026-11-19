extends SceneTree
## Headless integration smoke test. Requires a runnable Godot/Cgame binary.
## Run: godot --headless --path misc/advanced_physics --script res://tests/test_fluid_scene.gd

const WaterVolume = preload("res://addons/advanced_physics/water_volume_3d.gd")
const WindVolume = preload("res://addons/advanced_physics/wind_volume_3d.gd")
const FluidBody = preload("res://addons/advanced_physics/fluid_body_3d.gd")


func _initialize() -> void:
	call_deferred("_run")


func _add_box_shape(parent: CollisionObject3D, size: Vector3) -> void:
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = shape
	parent.add_child(collider)


func _add_test_body(scene: Node3D, pos: Vector3, mass: float) -> RigidBody3D:
	var body: RigidBody3D = RigidBody3D.new()
	body.position = pos
	body.mass = mass
	body.gravity_scale = 0.0 # isolate fluid force from the engine gravity
	body.collision_layer = 1
	body.collision_mask = 1
	scene.add_child(body)
	_add_box_shape(body, Vector3.ONE)
	var profile: CgameFluidBody3D = FluidBody.new()
	profile.displaced_volume = 1.0
	profile.drag_area = 1.0
	profile.sample_radius = 0.5
	profile.sample_offsets = [Vector3.ZERO]
	body.add_child(profile)
	return body


func _run() -> void:
	var scene: Node3D = Node3D.new()
	root.add_child(scene)

	var water: CgameWaterVolume3D = WaterVolume.new()
	water.position = Vector3(0.0, -3.0, 0.0)
	water.surface_height = 0.0
	water.fluid_density = 1000.0
	water.drag_coefficient = 0.0
	water.dynamic_viscosity = 0.0
	water.angular_drag_coefficient = 0.0
	water.collision_layer = 0
	water.collision_mask = 1
	scene.add_child(water)
	_add_box_shape(water, Vector3(8.0, 6.0, 8.0))

	var wind: CgameWindVolume3D = WindVolume.new()
	wind.position = Vector3(0.0, 3.0, 0.0)
	wind.wind_velocity = Vector3(8.0, 0.0, 0.0)
	wind.gust_amplitude = 0.0
	wind.collision_layer = 0
	wind.collision_mask = 1
	scene.add_child(wind)
	_add_box_shape(wind, Vector3(8.0, 6.0, 8.0))

	var floater: RigidBody3D = _add_test_body(scene, Vector3(0.0, -2.0, 0.0), 300.0)
	var flyer: RigidBody3D = _add_test_body(scene, Vector3(0.0, 3.0, 0.0), 1.0)

	for _step in range(14):
		await physics_frame

	var pass_water: bool = floater.linear_velocity.is_finite() and floater.linear_velocity.y > 0.0
	var pass_wind: bool = flyer.linear_velocity.is_finite() and flyer.linear_velocity.x > 0.0
	if pass_water and pass_wind:
		print("PASS: buoyancy and wind accelerate different rigid bodies through Area3D")
		quit(0)
	else:
		push_error("Physics smoke failed; water_y=%f, wind_x=%f" % [floater.linear_velocity.y, flyer.linear_velocity.x])
		quit(1)
