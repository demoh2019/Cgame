extends Node3D

const ResolutionController = preload("res://addons/visual_quality/adaptive_resolution.gd")
const FilmicSky = preload("res://addons/visual_quality/filmic_sky.gdshader")
const QualityManager = preload("res://addons/visual_quality/quality_manager.gd")
const AtmosphereController = preload("res://addons/visual_quality/atmosphere_controller.gd")
const ChunkedFoliage = preload("res://addons/visual_quality/foliage_chunks.gd")
const CharacterController = preload("res://addons/visual_quality/character_controller.gd")
const ExplorationQuest = preload("res://addons/visual_quality/exploration_quest.gd")

var controller: AdaptiveResolution3D
var manager: VisualQualityManager
var atmosphere: AtmosphereController3D
var foliage: ChunkedFoliage3D
var player_character: VisualLabCharacter3D
var movement_label: Label
var quest: ExplorationQuest3D
var quest_progress_label: Label
var quest_hint_label: Label
var sun_light: DirectionalLight3D
var weather_label: Label
var cycle_button: Button
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
	controller.enable_gpu_frame_measurement = true
	add_child(controller)
	manager = QualityManager.new()
	manager.name = "VisualQualityManager"
	manager.adaptive_controller = controller
	manager.target_environment = world_environment
	manager.settings_changed.connect(_update_graphics_ui)
	manager.settings_changed.connect(_update_foliage_quality)
	add_child(manager)
	foliage = ChunkedFoliage.new()
	foliage.name = "ChunkedFoliage3D"
	add_child(foliage)
	foliage.set_quality(manager.current_profile)
	_build_graphics_ui()
	_update_graphics_ui(manager.current_profile, manager.adaptive_enabled)
	atmosphere = AtmosphereController.new()
	atmosphere.name = "AtmosphereController3D"
	atmosphere.sun = sun_light
	atmosphere.environment = world_environment
	atmosphere.sky_material = sky_material
	atmosphere.animate_clouds = animate_clouds
	atmosphere.atmosphere_changed.connect(_update_atmosphere_ui)
	add_child(atmosphere)
	_build_atmosphere_ui()
	_update_atmosphere_ui(atmosphere.hour, atmosphere.overcast)
	quest = ExplorationQuest.new()
	quest.name = "ExplorationQuest3D"
	quest.player = player_character.get_view_camera()
	quest.progress_changed.connect(_on_quest_progress)
	quest.pickup_hint_changed.connect(_on_quest_hint)
	quest.quest_finished.connect(_on_quest_finished)
	add_child(quest)
	_build_quest_ui()
	_build_movement_ui()
	_on_quest_progress(quest.collected_count(), quest.positions.size())
	_on_quest_hint(quest.current_hint())


func _update_foliage_quality(profile: int, _adaptive: bool) -> void:
	if is_instance_valid(foliage):
		foliage.set_quality(profile)


func _process(delta: float) -> void:
	if status_label != null:
		status_label.text = "Visual Quality Lab | 1 Eco / 2 Balanced / 3 Cinematic\nFPS: %d | 3D scale: %.2f | %s\nWASD move | Space jump | Shift sprint | RMB look | V fly" % [
			Engine.get_frames_per_second(), get_viewport().scaling_3d_scale,
			RenderingServer.get_current_rendering_method()
		]


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				manager.set_profile(0)
			KEY_2:
				manager.set_profile(1)
			KEY_3:
				manager.set_profile(2)
			KEY_4:
				_toggle_hour()
			KEY_5:
				_toggle_weather()
			KEY_6:
				_toggle_cycle()
			KEY_R:
				_reset_quest()


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


func _build_atmosphere_ui() -> void:
	var ui: CanvasLayer = get_node("VisualQualityUI") as CanvasLayer
	var menu: HBoxContainer = HBoxContainer.new()
	menu.position = Vector2(18, 162)
	ui.add_child(menu)
	var time_button: Button = Button.new()
	time_button.text = "4: Day / Night"
	time_button.pressed.connect(_toggle_hour)
	menu.add_child(time_button)
	var weather_button: Button = Button.new()
	weather_button.text = "5: Clear / Cloudy"
	weather_button.pressed.connect(_toggle_weather)
	menu.add_child(weather_button)
	cycle_button = Button.new()
	cycle_button.pressed.connect(_toggle_cycle)
	menu.add_child(cycle_button)
	weather_label = Label.new()
	weather_label.position = Vector2(18, 206)
	ui.add_child(weather_label)


func _toggle_hour() -> void:
	atmosphere.set_hour(22.0 if atmosphere.hour >= 8.0 and atmosphere.hour < 18.0 else 14.0)


func _toggle_weather() -> void:
	atmosphere.set_overcast(0.0 if atmosphere.overcast >= 0.4 else 0.75)


func _toggle_cycle() -> void:
	atmosphere.set_auto_cycle(not atmosphere.auto_cycle)
	_update_atmosphere_ui(atmosphere.hour, atmosphere.overcast)


func _update_atmosphere_ui(hour: float, cloudiness: float) -> void:
	if not is_instance_valid(weather_label) or not is_instance_valid(cycle_button):
		return
	weather_label.text = "Time: %.1f h | Overcast: %.0f%% | Sky update: %.1f s" % [
		hour, cloudiness * 100.0, atmosphere.update_interval_seconds
	]
	cycle_button.text = "6: Cycle %s" % ("ON" if atmosphere.auto_cycle else "OFF")


func _build_quest_ui() -> void:
	var ui: CanvasLayer = get_node("VisualQualityUI") as CanvasLayer
	quest_progress_label = Label.new()
	quest_progress_label.position = Vector2(18, 248)
	quest_progress_label.add_theme_font_size_override("font_size", 19)
	quest_progress_label.add_theme_color_override("font_color", Color(0.35, 0.98, 1.0))
	ui.add_child(quest_progress_label)
	quest_hint_label = Label.new()
	quest_hint_label.position = Vector2(18, 280)
	ui.add_child(quest_hint_label)
	var reset_button: Button = Button.new()
	reset_button.text = "R: Restart light-shard quest"
	reset_button.position = Vector2(18, 314)
	reset_button.pressed.connect(_reset_quest)
	ui.add_child(reset_button)


func _reset_quest() -> void:
	if is_instance_valid(quest):
		quest.reset_quest()


func _on_quest_progress(collected: int, total: int) -> void:
	if is_instance_valid(quest_progress_label):
		quest_progress_label.text = "LIGHT SHARDS  %d / %d" % [collected, total]


func _on_quest_hint(message: String) -> void:
	if is_instance_valid(quest_hint_label):
		quest_hint_label.text = message


func _on_quest_finished() -> void:
	# A visible world-state consequence of the completed exploration goal.
	atmosphere.set_auto_cycle(false)
	atmosphere.set_overcast(0.0)
	atmosphere.set_hour(12.0)
	_on_quest_hint("Quest complete: you restored the forest light! Press R to replay.")


func _build_movement_ui() -> void:
	var ui: CanvasLayer = get_node("VisualQualityUI") as CanvasLayer
	movement_label = Label.new()
	movement_label.position = Vector2(18, 358)
	ui.add_child(movement_label)
	var toggle: Button = Button.new()
	toggle.text = "V: Toggle walk / fly"
	toggle.position = Vector2(18, 390)
	toggle.pressed.connect(_toggle_player_mode)
	ui.add_child(toggle)
	player_character.movement_mode_changed.connect(_update_movement_mode)
	_update_movement_mode(player_character.is_flying)


func _toggle_player_mode() -> void:
	player_character.set_fly_mode(not player_character.is_flying)


func _update_movement_mode(is_flying: bool) -> void:
	if is_instance_valid(movement_label):
		movement_label.text = "Character mode: %s" % ("FLY  |  Q/E vertical" if is_flying else "WALK  |  Space jump")


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

	sun_light = DirectionalLight3D.new()
	sun_light.name = "Sun"
	sun_light.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	sun_light.light_energy = 1.4
	sun_light.shadow_enabled = true
	add_child(sun_light)

	# Physics floor and visible surface are separate, so the player cannot fall through.
	var static_ground: StaticBody3D = StaticBody3D.new()
	static_ground.name = "GroundCollision"
	var ground_collision: CollisionShape3D = CollisionShape3D.new()
	var ground_box: BoxShape3D = BoxShape3D.new()
	ground_box.size = Vector3(85.0, 0.4, 85.0)
	ground_collision.shape = ground_box
	static_ground.position.y = -0.2
	static_ground.add_child(ground_collision)
	add_child(static_ground)

	var floor: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(85, 85)
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
		var obstacle: StaticBody3D = StaticBody3D.new()
		obstacle.name = "Obstacle_%d" % i
		var obstacle_shape: CollisionShape3D = CollisionShape3D.new()
		if i % 2 == 0:
			var sphere_shape: SphereShape3D = SphereShape3D.new()
			sphere_shape.radius = 1.0
			obstacle_shape.shape = sphere_shape
		else:
			var cube_shape: BoxShape3D = BoxShape3D.new()
			cube_shape.size = Vector3.ONE * 2.0
			obstacle_shape.shape = cube_shape
		obstacle.add_child(obstacle_shape)
		object.add_child(obstacle)

	player_character = CharacterController.new()
	player_character.name = "Player"
	player_character.position = Vector3(0.0, 0.2, 6.0)
	add_child(player_character)
	player_character.get_view_camera().look_at(Vector3(0.0, 1.4, -12.0))

	var ui: CanvasLayer = CanvasLayer.new()
	ui.name = "VisualQualityUI"
	add_child(ui)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 18)
	status_label.position = Vector2(18, 18)
	status_label.add_theme_color_override("font_color", Color(0.98, 0.98, 1.0))
	ui.add_child(status_label)
