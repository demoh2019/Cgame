extends Node3D
## Press W to toggle wind, T to tear stressed links, R to reset.

const XPBDObject = preload("res://addons/cgame_xpbd/xpbd_object_3d.gd")

var rope: CgameXPBDObject3D
var cloth: CgameXPBDObject3D
var windy: bool = false
var info: Label


func _ready() -> void:
	_create_scene()
	_create_objects()
	_create_hud()


func _create_scene() -> void:
	var camera: Camera3D = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(3.0, 5.0, 16.0)
	camera.look_at(Vector3(0.0, 2.0, 0.0))
	camera.current = true
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	add_child(sun)
	sun.rotation_degrees = Vector3(-50.0, 15.0, 0.0)

	var floor_mesh: PlaneMesh = PlaneMesh.new()
	floor_mesh.size = Vector2(30.0, 30.0)
	var floor_visual: MeshInstance3D = MeshInstance3D.new()
	floor_visual.mesh = floor_mesh
	floor_visual.position.y = -1.0
	add_child(floor_visual)

	var sphere_mesh: SphereMesh = SphereMesh.new()
	sphere_mesh.radius = 1.15
	sphere_mesh.height = 2.3
	var sphere_visual: MeshInstance3D = MeshInstance3D.new()
	sphere_visual.mesh = sphere_mesh
	sphere_visual.position = Vector3(2.5, 0.2, 0.0)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.42, 0.22)
	sphere_visual.material_override = material
	add_child(sphere_visual)


func _create_objects() -> void:
	rope = XPBDObject.new()
	rope.name = "TearableRope"
	rope.simulation_mode = CgameXPBDObject3D.Mode.ROPE
	rope.rope_start = Vector3(-5.0, 5.0, 0.0)
	rope.rope_end = Vector3(0.0, 3.0, 0.0)
	rope.segments = 26
	rope.tearing_strain = 0.8
	rope.enable_floor = true
	rope.floor_world_height = -1.0
	rope.line_color = Color(0.15, 0.85, 1.0)
	add_child(rope)

	cloth = XPBDObject.new()
	cloth.name = "ClothSheet"
	cloth.simulation_mode = CgameXPBDObject3D.Mode.CLOTH
	cloth.cloth_columns = 18
	cloth.cloth_rows = 12
	cloth.cloth_origin = Vector3(0.0, 5.5, 0.0)
	cloth.tearing_strain = 0.8
	cloth.enable_floor = true
	cloth.floor_world_height = -1.0
	cloth.enable_sphere = true
	cloth.sphere_world_center = Vector3(2.5, 0.2, 0.0)
	cloth.sphere_radius = 1.15
	cloth.line_color = Color(0.98, 0.84, 0.22)
	add_child(cloth)


func _create_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	info = Label.new()
	info.position = Vector2(12.0, 12.0)
	layer.add_child(info)
	_update_hud()


func _update_hud() -> void:
	info.text = "Cgame XPBD lab - rope + cloth\nW: wind   T: tear   R: reset\nWind: %s | Blue rope, yellow cloth" % ("ON" if windy else "OFF")


func _apply_wind() -> void:
	var target: Vector3 = Vector3(12.0, 0.0, 7.0) if windy else Vector3.ZERO
	rope.wind_velocity = target
	cloth.wind_velocity = target
	_update_hud()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_W:
			windy = not windy
			_apply_wind()
		KEY_R:
			rope.rebuild()
			cloth.rebuild()
		KEY_T:
			var rope_index: int = rope.solver.particle_count() / 2
			rope.solver.positions[rope_index] += Vector3(4.0, -4.0, 0.0)
			var cloth_index: int = cloth.solver.particle_count() / 2
			cloth.solver.positions[cloth_index] += Vector3(0.0, -5.0, 3.0)
