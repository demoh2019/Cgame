extends Node3D

const ResolutionController = preload("res://addons/visual_quality/adaptive_resolution.gd")
const FilmicSky = preload("res://addons/visual_quality/filmic_sky.gdshader")
const QualityManager = preload("res://addons/visual_quality/quality_manager.gd")
const AtmosphereController = preload("res://addons/visual_quality/atmosphere_controller.gd")
const WorldStreamer = preload("res://addons/visual_quality/world_streamer.gd")
const WorldStateStore = preload("res://addons/visual_quality/world_state_store.gd")
const AIInterest = preload("res://addons/visual_quality/ai_interest_manager.gd")
const Telemetry = preload("res://addons/visual_quality/world_telemetry.gd")
const BudgetGovernor = preload("res://addons/visual_quality/world_budget_governor.gd")
const CharacterController = preload("res://addons/visual_quality/character_controller.gd")
const ExplorationQuest = preload("res://addons/visual_quality/exploration_quest.gd")

var controller: AdaptiveResolution3D
var manager: VisualQualityManager
var atmosphere: AtmosphereController3D
var streamer: WorldStreamer3D
var world_state: WorldStateStore3D
var world_state_label: Label
var ai_simulation_enabled: bool = true
var ai_interest: WorldAIInterestManager3D
var telemetry: WorldTelemetry3D
var governor: WorldBudgetGovernor3D
var telemetry_label: Label
var last_export_result: String = ""
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
	streamer = WorldStreamer.new()
	streamer.name = "WorldStreamer3D"
	streamer.cell_size = 14.0
	streamer.source = player_character
	streamer.streaming_enabled = false
	streamer.cell_loaded.connect(_on_streamed_cell_loaded)
	# Each forest section is a reusable PackedScene, not a permanent world node.
	for z in range(-3, 4):
		for x in range(-3, 4):
			streamer.register_scene_cell(Vector2i(x, z), "res://world/forest_cell.tscn")
	world_state = WorldStateStore.new()
	world_state.name = "WorldStateStore3D"
	world_state.streamer = streamer
	world_state.world_id = "visual_quality_lab_forest_20261120"
	world_state.state_saved.connect(_on_world_state_saved)
	# The store subscribes before the first scene is streamed.
	add_child(world_state)
	add_child(streamer)
	streamer.streaming_enabled = true
	streamer.set_quality_profile(manager.current_profile)
	ai_interest = AIInterest.new()
	ai_interest.name = "WorldAIInterestManager3D"
	ai_interest.streamer = streamer
	ai_interest.player = player_character
	add_child(ai_interest)
	ai_interest.set_quality_profile(manager.current_profile)
	telemetry = Telemetry.new()
	telemetry.name = "WorldTelemetry3D"
	telemetry.streamer = streamer
	telemetry.ai_interest = ai_interest
	telemetry.snapshot_captured.connect(_update_telemetry_ui)
	add_child(telemetry)
	governor = BudgetGovernor.new()
	governor.name = "WorldBudgetGovernor3D"
	governor.streamer = streamer
	governor.ai_interest = ai_interest
	governor.telemetry = telemetry
	add_child(governor)
	governor.set_quality_profile(manager.current_profile)
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
	_build_world_state_ui()
	_build_telemetry_ui()
	_on_quest_progress(quest.collected_count(), quest.positions.size())
	_on_quest_hint(quest.current_hint())


func _update_foliage_quality(profile: int, _adaptive: bool) -> void:
	if is_instance_valid(streamer):
		for cell in streamer.get_active_cells():
			if cell.has_method("set_quality"):
				cell.call("set_quality", profile)
		streamer.set_quality_profile(profile)
	if is_instance_valid(ai_interest):
		ai_interest.set_quality_profile(profile)
	if is_instance_valid(governor):
		governor.set_quality_profile(profile)


func _on_streamed_cell_loaded(_coord: Vector2i, cell: Node3D) -> void:
	if cell.has_method("set_quality"):
		cell.call("set_quality", manager.current_profile)
	if cell.has_method("set_ai_enabled"):
		cell.call("set_ai_enabled", ai_simulation_enabled)


func _process(delta: float) -> void:
	if status_label != null:
		var npc_counts: Vector2i = _count_npc_behaviors()
		status_label.text = "Visual Quality Lab | 1 Eco / 2 Balanced / 3 Cinematic\nFPS: %d | 3D scale: %.2f | %s\nWASD move | Space jump | Shift sprint | RMB look | V fly\nWorld cells: %d/%d | Pending assets: %d | 7 Streaming: %s\nNPCs: %d | Alerted: %d | Sleeping: %d | AI budget: %d us | 9 AI: %s" % [
			Engine.get_frames_per_second(), get_viewport().scaling_3d_scale,
			RenderingServer.get_current_rendering_method(),
			streamer.active_cell_count(), streamer.registered_cell_count(),
			streamer.pending_asset_count(), "ON" if streamer.streaming_enabled else "OFF",
			npc_counts.x, npc_counts.y, ai_interest.sleeping_npc_count(),
			ai_interest.last_update_micros, "ON" if ai_simulation_enabled else "OFF"
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
			KEY_7:
				streamer.streaming_enabled = not streamer.streaming_enabled
			KEY_G:
				_try_activate_world_beacon()
			KEY_8:
				_reset_world_beacons()
			KEY_9:
				_toggle_ai_simulation()
			KEY_0:
				_toggle_telemetry_ui()
			KEY_P:
				_export_telemetry_csv()
			KEY_B:
				_toggle_budget_governor()


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


func _build_world_state_ui() -> void:
	var ui: CanvasLayer = get_node("VisualQualityUI") as CanvasLayer
	world_state_label = Label.new()
	world_state_label.position = Vector2(18, 433)
	world_state_label.add_theme_color_override("font_color", Color(0.82, 1.0, 0.58))
	ui.add_child(world_state_label)
	var reset_button: Button = Button.new()
	reset_button.text = "8: Reset forest beacons"
	reset_button.position = Vector2(18, 465)
	reset_button.pressed.connect(_reset_world_beacons)
	ui.add_child(reset_button)
	_update_world_state_ui()


func _try_activate_world_beacon() -> void:
	if not is_instance_valid(streamer) or not is_instance_valid(player_character):
		return
	var eyes: Vector3 = player_character.global_position + Vector3.UP * 0.8
	var nearest: Node3D
	var nearest_distance_sq: float = 2.8 * 2.8
	for cell in streamer.get_active_cells():
		if not cell.has_method("try_activate_beacon"):
			continue
		if cell.get("beacon_activated") == true:
			continue
		var distance_sq: float = eyes.distance_squared_to(cell.call("get_beacon_world_position"))
		if distance_sq <= nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest = cell
	if nearest != null:
		nearest.call("try_activate_beacon", eyes, 2.8)
	_update_world_state_ui()


func _reset_world_beacons() -> void:
	if is_instance_valid(world_state):
		world_state.clear_all_states()
	_update_world_state_ui()


func _on_world_state_saved(_path: String, _count: int) -> void:
	_update_world_state_ui()


func _update_world_state_ui() -> void:
	if is_instance_valid(world_state_label) and is_instance_valid(world_state):
		world_state_label.text = "G: Activate a nearby orange beacon  |  Saved cells: %d" % world_state.saved_cell_count()


func _toggle_ai_simulation() -> void:
	ai_simulation_enabled = not ai_simulation_enabled
	ai_interest.set_global_enabled(ai_simulation_enabled)


func _count_npc_behaviors() -> Vector2i:
	var active_npcs: int = 0
	var alerted_npcs: int = 0
	if not is_instance_valid(streamer):
		return Vector2i.ZERO
	for cell in streamer.get_active_cells():
		if not cell.has_method("get_active_npc"):
			continue
		var npc: StreamedPatrolNPC3D = cell.call("get_active_npc")
		if is_instance_valid(npc):
			active_npcs += 1
			if npc.behavior == StreamedPatrolNPC3D.Behavior.ALERT:
				alerted_npcs += 1
	return Vector2i(active_npcs, alerted_npcs)


func _build_telemetry_ui() -> void:
	var ui: CanvasLayer = get_node("VisualQualityUI") as CanvasLayer
	telemetry_label = Label.new()
	telemetry_label.name = "WorldTelemetryHUD"
	telemetry_label.position = Vector2(18, 510)
	telemetry_label.add_theme_font_size_override("font_size", 14)
	telemetry_label.add_theme_color_override("font_color", Color(0.86, 0.92, 0.54))
	ui.add_child(telemetry_label)
	_update_telemetry_ui(telemetry.sample_now())


func _update_telemetry_ui(snapshot: Dictionary) -> void:
	if not is_instance_valid(telemetry_label) or not is_instance_valid(governor):
		return
	telemetry_label.text = "World profiler | 0 HUD | P Export CSV | B Auto budget: %s\nCPU avg: %.2f ms | CPU p95: %.2f ms | Physics: %.2f ms\nStreaming: %d us | spawned %d / unloaded %d | AI: %d us\nBudgets: %d spawns / %d AI cells | snapshots: %d\n%s" % [
		"ON" if governor.automatic_enabled else "OFF",
		float(snapshot.get("cpu_ms", 0.0)), telemetry.get_cpu_p95_ms(),
		float(snapshot.get("physics_ms", 0.0)),
		int(snapshot.get("streamer_us", 0)), int(snapshot.get("spawned", 0)),
		int(snapshot.get("unloaded", 0)), int(snapshot.get("ai_us", 0)),
		governor.current_spawn_budget(), governor.current_ai_budget(),
		telemetry.sample_count(), last_export_result
	]


func _toggle_telemetry_ui() -> void:
	if is_instance_valid(telemetry_label):
		telemetry_label.visible = not telemetry_label.visible


func _export_telemetry_csv() -> void:
	if not is_instance_valid(telemetry):
		return
	var code: Error = telemetry.export_csv()
	last_export_result = "CSV: %s" % (telemetry.csv_path if code == OK else "export failed (%d)" % code)
	_update_telemetry_ui(telemetry.get_latest())


func _toggle_budget_governor() -> void:
	if is_instance_valid(governor):
		governor.set_automatic_enabled(not governor.automatic_enabled)
		_update_telemetry_ui(telemetry.get_latest())


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
	ground_box.size = Vector3(112.0, 0.4, 112.0)
	ground_collision.shape = ground_box
	static_ground.position.y = -0.2
	static_ground.add_child(ground_collision)
	add_child(static_ground)

	var floor: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(112, 112)
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
			var box_mesh: BoxMesh = BoxMesh.new()
			box_mesh.size = Vector3.ONE * 2.0
			object.mesh = box_mesh
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
