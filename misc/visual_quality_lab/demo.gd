extends Node3D

const ResolutionController = preload("res://addons/visual_quality/adaptive_resolution.gd")
const FilmicSky = preload("res://addons/visual_quality/filmic_sky.gdshader")
const QualityManager = preload("res://addons/visual_quality/quality_manager.gd")

var controller: AdaptiveResolution3D
var manager: VisualQualityManager
var mode_label: Label
var adaptive_button: Button
var world_environment: Environment
var status_label: Label
var sky_material: ShaderMaterial
var cloud_elapsed: float = 0.0
@export var animate_clouds: bool = false


func _ready() -> void:
	_build_world()
	controller = ResolutionController.new()
	controller.name = "AdaptiveResolution3D"
	add_child(controller)
	manager = QualityManager.new()
	manager.name = "VisualQualityManager"
	manager.adaptive_controller = controller
	manager.target_environment = world_environment
	manager.settings_changed.connect(_update_graphics_ui)
	add_child(manager)
	_build_graphics_ui()
	_update_graphics_ui(manager.current_profile, manager.adaptive_enabled)


func _process(delta: float) -> void:
	if status_label != null:
		status_label.text = "Visual Quality Lab | 1 Eco / 2 Balanced / 3 Cinematic\nFPS: %d | 3D scale: %.2f | %s" % [
			Engine.get_frames_per_second(), get_viewport().scaling_3d_scale,
			RenderingServer.get_current_rendering_method()
		]
	if animate_clouds:
		cloud_elapsed += delta
		if cloud_elapsed >= 0.35:
			cloud_elapsed = 0.0
			sky_material.set_shader_parameter("cloud_time", Time.get_ticks_msec() * 0.00004)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				manager.set_profile(0)
			KEY_2:
				manager.set_profile(1)
			KEY_3:
				manager.set_profile(2)


func _build_graphics_ui() -> void:
	var ui: CanvasLayer = get_node("VisualQualityUI") as CanvasLayer
	var menu: HBoxContainer = HBoxContainer.new()
	menu.position = Vector2(18, 86)
	ui.add_child(menu)
	for i in range(3):
		var button: Button = Button.new()
		button.text = ["Eco", "Balanced", "Cinematic"][i]
		button.pressed.connect(manager.set_profile.bind(i))
		menu.add_child(button)
	adaptive_button = Button.new()
	adaptive_button.pressed.connect(_toggle_adaptive)
	menu.add_child(adaptive_button)
	mode_label = Label.new()
	mode_label.position = Vector2(18, 132)
	ui.add_child(mode_label)


func _toggle_adaptive() -> void:
	manager.set_adaptive_enabled(not manager.adaptive_enabled)


func _update_graphics_ui(profile: int, adaptive: bool) -> void:
	if not is_instance_valid(mode_label) or not is_instance_valid(adaptive_button):
		return
	var names: PackedStringArray = PackedStringArray(["Eco", "Balanced", "Cinematic"])
	mode_label.text = "Mode: %s | Adaptive: %s | settings persisted" % [names[profile], "ON" if adaptive else "OFF"]
	adaptive_button.text = "Adaptive: %s" % ("ON" if adaptive else "OFF")


func _build_world() -> void:
	sky_material = ShaderMaterial.new()
	sky_material.shader = FilmicSky
	var sky: Sky = Sky.new()
	sky.sky_material = sky_material
	world_environment = Environment.new()
	world_environment.background_mode = Environment.BG_SKY
	world_environment.sky = sky
	world_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = world_environment
	add_child(world)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)

	var floor: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor.mesh = plane
	var floor_material: StandardMaterial3D = StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.15, 0.22, 0.24)
	floor_material.roughness = 0.75
	floor.material_override = floor_material
	add_child(floor)

	for i in range(8):
		var object: MeshInstance3D = MeshInstance3D.new()
		if i % 2 == 0:
			object.mesh = SphereMesh.new()
		else:
			object.mesh = BoxMesh.new()
		object.position = Vector3(float(i - 4) * 2.15 + 1.0, 1.1, 0.0)
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color.from_hsv(float(i) / 8.0, 0.65, 0.85)
		material.metallic = 0.7 if i % 2 == 0 else 0.1
		material.roughness = 0.12 + 0.10 * float(i)
		object.material_override = material
		add_child(object)

	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0.0, 6.5, 19.5)
	camera.fov = 64.0
	add_child(camera)
	camera.look_at(Vector3(0, 1, 0))
	camera.current = true

	var ui: CanvasLayer = CanvasLayer.new()
	ui.name = "VisualQualityUI"
	add_child(ui)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 18)
	status_label.position = Vector2(18, 18)
	status_label.add_theme_color_override("font_color", Color(0.98, 0.98, 1.0))
	ui.add_child(status_label)
