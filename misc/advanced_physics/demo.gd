extends Node3D
## Standalone interactive scene for the optional advanced fluid physics addon.
## W: toggle wind, B: spawn a buoyant box, R: reset boxes.

const WaterVolume = preload("res://addons/advanced_physics/water_volume_3d.gd")
const WindVolume = preload("res://addons/advanced_physics/wind_volume_3d.gd")
const FluidBody = preload("res://addons/advanced_physics/fluid_body_3d.gd")

var _bodies: Array[RigidBody3D] = []
var _wind: CgameWindVolume3D
var _spawn_count: int = 0
var _help_label: Label


func _ready() -> void:
	_create_environment()
	_create_floor()
	_create_water()
	_create_wind()
	_create_hud()
	_reset_boxes()


func _create_environment() -> void:
	var camera: Camera3D = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(12.0, 8.0, 15.0)
	camera.look_at(Vector3(0.0, -2.0, 0.0))
	camera.current = true

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	add_child(sun)
	sun.rotation_degrees = Vector3(-55.0, 25.0, 0.0)


func _make_box_collision(parent: CollisionObject3D, size: Vector3) -> void:
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = shape
	parent.add_child(collider)


func _make_box_mesh(parent: Node3D, size: Vector3, tint: Color, transparent: bool = false) -> void:
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = tint
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = box
	visual.material_override = material
	parent.add_child(visual)


func _create_floor() -> void:
	var ground: StaticBody3D = StaticBody3D.new()
	ground.position = Vector3(0.0, -8.0, 0.0)
	add_child(ground)
	_make_box_collision(ground, Vector3(26.0, 1.0, 26.0))
	_make_box_mesh(ground, Vector3(26.0, 1.0, 26.0), Color(0.23, 0.26, 0.3))


func _create_water() -> void:
	var water: CgameWaterVolume3D = WaterVolume.new()
	water.name = "WaterVolume"
	water.position = Vector3(0.0, -3.5, 0.0)
	water.surface_height = 0.0
	water.fluid_velocity = Vector3(0.5, 0.0, 0.0)
	water.collision_layer = 0
	water.collision_mask = 1
	add_child(water)
	_make_box_collision(water, Vector3(24.0, 7.0, 24.0))

	var surface_mesh: PlaneMesh = PlaneMesh.new()
	surface_mesh.size = Vector2(24.0, 24.0)
	var surface_material: StandardMaterial3D = StandardMaterial3D.new()
	surface_material.albedo_color = Color(0.06, 0.44, 0.85, 0.4)
	surface_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var surface: MeshInstance3D = MeshInstance3D.new()
	surface.mesh = surface_mesh
	surface.material_override = surface_material
	add_child(surface)


func _create_wind() -> void:
	_wind = WindVolume.new()
	_wind.name = "WindVolume"
	_wind.position = Vector3(0.0, 6.0, 0.0)
	_wind.wind_velocity = Vector3(14.0, 0.0, 0.0)
	_wind.gust_amplitude = 4.0
	_wind.gust_frequency_hz = 0.45
	_wind.collision_layer = 0
	_wind.collision_mask = 1
	add_child(_wind)
	_make_box_collision(_wind, Vector3(24.0, 12.0, 24.0))


func _create_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_help_label = Label.new()
	_help_label.position = Vector2(16.0, 16.0)
	layer.add_child(_help_label)
	_update_hud()


func _update_hud() -> void:
	_help_label.text = "Cgame Advanced Physics: buoyancy + wind\nW: wind on/off  |  B: add buoyant box  |  R: reset\nWind: %s  |  blue floats, orange sinks" % ("ON" if _wind.enabled else "OFF")


func _spawn_box(where: Vector3, body_mass: float, color: Color) -> void:
	var body: RigidBody3D = RigidBody3D.new()
	body.position = where
	body.mass = body_mass
	body.rotation_degrees = Vector3(0.0, 0.0, 8.0)
	body.name = "FloatingBox_%d" % _spawn_count
	_spawn_count += 1
	add_child(body)
	_make_box_collision(body, Vector3.ONE)
	_make_box_mesh(body, Vector3.ONE, color)

	var profile: CgameFluidBody3D = FluidBody.new()
	profile.name = "FluidBody3D"
	profile.displaced_volume = 1.0
	profile.drag_area = 1.0
	profile.sample_radius = 0.5
	profile.sample_offsets = [
		Vector3(-0.35, 0.0, -0.35),
		Vector3(-0.35, 0.0, 0.35),
		Vector3(0.35, 0.0, -0.35),
		Vector3(0.35, 0.0, 0.35),
	]
	body.add_child(profile)
	body.angular_velocity = Vector3(0.0, 0.0, 0.5)
	_bodies.append(body)


func _reset_boxes() -> void:
	for body in _bodies:
		if is_instance_valid(body):
			body.queue_free()
	_bodies.clear()
	_spawn_box(Vector3(-2.0, 3.5, 0.0), 450.0, Color(0.25, 0.65, 1.0))
	_spawn_box(Vector3(2.0, 4.5, 0.0), 1400.0, Color(1.0, 0.5, 0.2))


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_W:
			_wind.enabled = not _wind.enabled
			_update_hud()
		KEY_B:
			_spawn_box(Vector3(-3.0 + float(_spawn_count % 6), 5.5, -2.0), 400.0, Color(0.55, 0.9, 0.45))
		KEY_R:
			_reset_boxes()
