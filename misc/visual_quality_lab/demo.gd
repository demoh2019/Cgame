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
const StreamingInspector = preload("res://addons/visual_quality/world_streaming_inspector.gd")
const CharacterController = preload("res://addons/visual_quality/character_controller.gd")
const ExplorationQuest = preload("res://addons/visual_quality/exploration_quest.gd")
const InteractionRouter = preload("res://addons/visual_quality/world_interaction_router.gd")
const Inventory = preload("res://addons/visual_quality/inventory_component.gd")
const ItemCatalog = preload("res://addons/visual_quality/item_catalog.gd")
const Attributes = preload("res://addons/visual_quality/attribute_component.gd")
const Abilities = preload("res://addons/visual_quality/ability_component.gd")
const Combatant = preload("res://addons/visual_quality/combat_component.gd")
const CombatDirector = preload("res://addons/visual_quality/combat_controller.gd")

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
var streaming_inspector: WorldStreamingInspector3D
var telemetry_label: Label
var last_export_result: String = ""
var player_character: VisualLabCharacter3D
var movement_label: Label
var quest: ExplorationQuest3D
var inventory: WorldInventory3D
var player_attributes: WorldAttributes3D
var player_abilities: WorldAbilitySystem3D
var player_combatant: WorldCombatant3D
var combat_director: WorldCombatDirector3D
var combat_label: Label
var sentries_defeated: int = 0
var inventory_panel: PanelContainer
var inventory_label: Label
var inventory_feedback: Label
var equipped_lantern: OmniLight3D
var interaction_router: WorldInteractionRouter3D
var interaction_label: Label
var interaction_result_label: Label
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
	inventory = Inventory.new()
	inventory.name = "WorldInventory3D"
	inventory.world_id = "visual_quality_lab_forest_20261120"
	inventory.inventory_changed.connect(_update_inventory_ui)
	inventory.equipment_changed.connect(_on_equipment_changed)
	add_child(inventory)
	player_attributes = Attributes.new()
	player_attributes.name = "WorldAttributes3D"
	player_character.add_child(player_attributes)
	player_character.attributes = player_attributes
	player_abilities = Abilities.new()
	player_abilities.name = "WorldAbilitySystem3D"
	player_abilities.attributes = player_attributes
	player_character.add_child(player_abilities)
	player_combatant = Combatant.new()
	player_combatant.name = "PlayerCombatant"
	player_combatant.team_id = WorldCombatant3D.TEAM_PLAYER
	player_combatant.attributes = player_attributes
	player_combatant.armor = 15.0
	player_combatant.defeated.connect(_on_player_defeated)
	player_character.add_child(player_combatant)
	# v15 inventory files have no equipment key: default to no gear.
	for slot in inventory.equipped_snapshot().keys():
		_on_equipment_changed(slot, inventory.get_equipped_item(slot))
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
	# Upgrade old saves with already activated beacons. Unique source IDs
	# make this migration safe after recipes consume some essence.
	for z in range(-3, 4):
		for x in range(-3, 4):
			var coord: Vector2i = Vector2i(x, z)
			if world_state.get_saved_state(coord).get("activated", false) == true:
				inventory.grant_once("beacon:%d:%d" % [x, z], "forest_essence", 1)
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
	streaming_inspector = StreamingInspector.new()
	streaming_inspector.name = "WorldStreamingInspector3D"
	streaming_inspector.streamer = streamer
	add_child(streaming_inspector)
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
	quest.shard_collected.connect(_on_shard_collected)
	add_child(quest)
	# Migrate quest saves from earlier versions once. Stable source IDs mean
	# crafting and quest replay cannot mint duplicate shard rewards.
	inventory.import_quest_history(quest.world_seed, quest.collected_ids)
	_build_quest_ui()
	_build_movement_ui()
	_build_world_state_ui()
	_build_telemetry_ui()
	interaction_router = InteractionRouter.new()
	interaction_router.name = "WorldInteractionRouter3D"
	interaction_router.streamer = streamer
	interaction_router.quest = quest
	interaction_router.player = player_character
	interaction_router.camera = player_character.get_view_camera()
	interaction_router.focused_action_changed.connect(_on_interaction_focus_changed)
	interaction_router.interaction_completed.connect(_on_interaction_completed)
	add_child(interaction_router)
	_build_interaction_ui()
	_build_inventory_ui()
	_build_equipped_lantern()
	combat_director = CombatDirector.new()
	combat_director.name = "WorldCombatDirector3D"
	combat_director.streamer = streamer
	combat_director.player = player_character
	combat_director.camera = player_character.get_view_camera()
	combat_director.player_combatant = player_combatant
	combat_director.player_attributes = player_attributes
	combat_director.combat_message.connect(_on_combat_message)
	add_child(combat_director)
	_build_combat_ui()
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
	if cell.has_signal("resource_awarded"):
		cell.connect("resource_awarded", _on_world_resource_awarded)
	if cell.has_signal("sentry_defeated"):
		cell.connect("sentry_defeated", _on_sentry_defeated)


func _process(delta: float) -> void:
	if status_label != null:
		var npc_counts: Vector2i = _count_npc_behaviors()
		status_label.text = "Visual Quality Lab | 1 Eco / 2 Balanced / 3 Cinematic\nFPS: %d | 3D scale: %.2f | %s\nWASD move | Space jump | Shift sprint | RMB look | V fly\nWorld cells: %d/%d | Pending assets: %d | 7 Streaming: %s\nNPCs: %d | Alerted: %d | Sleeping: %d | AI budget: %d us | 9 AI: %s\nHP %.0f/%.0f | Stamina %.0f/%.0f | Move x%.2f | X Dash %.1fs | Z Focus %.1fs\nCombat M strike | N stun wave | Backspace respawn | Kills: %d" % [
			Engine.get_frames_per_second(), get_viewport().scaling_3d_scale,
			RenderingServer.get_current_rendering_method(),
			streamer.active_cell_count(), streamer.registered_cell_count(),
			streamer.pending_asset_count(), "ON" if streamer.streaming_enabled else "OFF",
			npc_counts.x, npc_counts.y, ai_interest.sleeping_npc_count(),
			ai_interest.last_update_micros, "ON" if ai_simulation_enabled else "OFF",
			player_attributes.health, player_attributes.get_stat("max_health"),
			player_attributes.stamina, player_attributes.get_stat("max_stamina"),
			player_attributes.get_stat("move_speed"), player_abilities.get_cooldown("dash"),
			player_abilities.get_cooldown("focus"), sentries_defeated
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
			KEY_K:
				streaming_inspector.toggle_visible()
			KEY_L:
				_export_cell_hotspots()
			KEY_I:
				_toggle_inventory_ui()
			KEY_C:
				_craft_inventory_item("spark_core")
			KEY_J:
				_craft_inventory_item("forest_lantern")
			KEY_T:
				_toggle_equipped_lantern()
			KEY_U:
				_craft_inventory_item("trail_boots")
			KEY_Y:
				_toggle_trail_boots()
			KEY_X:
				_activate_player_ability("dash")
			KEY_Z:
				_activate_player_ability("focus")
			KEY_M:
				if is_instance_valid(combat_director):
					combat_director.request_strike()
			KEY_N:
				if is_instance_valid(combat_director):
					combat_director.request_shockwave()
			KEY_BACKSPACE:
				_respawn_player()


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


func _export_cell_hotspots() -> void:
	if not is_instance_valid(streaming_inspector):
		return
	var result: Error = streaming_inspector.export_hotspot_csv()
	last_export_result = "Cell hotspots: %s" % (streaming_inspector.hotspot_csv_path
		if result == OK else "export failed (%d)" % result)
	_update_telemetry_ui(telemetry.get_latest())


func _build_interaction_ui() -> void:
	var ui: CanvasLayer = get_node("VisualQualityUI") as CanvasLayer
	interaction_label = Label.new()
	interaction_label.name = "WorldInteractionPrompt"
	interaction_label.anchor_left = 0.5
	interaction_label.anchor_right = 1.0
	interaction_label.anchor_top = 1.0
	interaction_label.anchor_bottom = 1.0
	interaction_label.offset_left = 12.0
	interaction_label.offset_right = -18.0
	interaction_label.offset_top = -84.0
	interaction_label.offset_bottom = -50.0
	interaction_label.add_theme_font_size_override("font_size", 19)
	interaction_label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.61))
	ui.add_child(interaction_label)
	interaction_result_label = Label.new()
	interaction_result_label.name = "WorldInteractionFeedback"
	interaction_result_label.anchor_left = 0.5
	interaction_result_label.anchor_right = 1.0
	interaction_result_label.anchor_top = 1.0
	interaction_result_label.anchor_bottom = 1.0
	interaction_result_label.offset_left = 12.0
	interaction_result_label.offset_right = -18.0
	interaction_result_label.offset_top = -45.0
	interaction_result_label.offset_bottom = -12.0
	ui.add_child(interaction_result_label)
	_on_interaction_focus_changed("", "")


func _on_interaction_focus_changed(label: String, _stable_id: String) -> void:
	if is_instance_valid(interaction_label):
		interaction_label.text = ("H: %s" % label if not label.is_empty()
			else "H: Посмотрите на предмет, маяк или стража")


func _on_interaction_completed(_stable_id: String, success: bool, message: String) -> void:
	if is_instance_valid(interaction_result_label):
		interaction_result_label.text = message if success else "Действие недоступно"
	_update_world_state_ui()


func _on_shard_collected(index: int) -> void:
	inventory.grant_once("quest:%d:%d" % [quest.world_seed, index], "light_shard", 1)


func _on_world_resource_awarded(item_id: String, source_uid: String) -> void:
	inventory.grant_once(source_uid, item_id, 1)


func _build_inventory_ui() -> void:
	var ui: CanvasLayer = get_node("VisualQualityUI") as CanvasLayer
	inventory_panel = PanelContainer.new()
	inventory_panel.name = "WorldInventoryPanel"
	inventory_panel.anchor_left = 0.5
	inventory_panel.anchor_right = 0.5
	inventory_panel.anchor_top = 0.5
	inventory_panel.anchor_bottom = 0.5
	inventory_panel.offset_left = -190.0
	inventory_panel.offset_right = 190.0
	inventory_panel.offset_top = -145.0
	inventory_panel.offset_bottom = 145.0
	ui.add_child(inventory_panel)
	var column: VBoxContainer = VBoxContainer.new()
	inventory_panel.add_child(column)
	var heading: Label = Label.new()
	heading.text = "ИНВЕНТАРЬ  |  I закрыть  |  T фонарь  |  Y сапоги"
	column.add_child(heading)
	inventory_label = Label.new()
	column.add_child(inventory_label)
	var craft_core: Button = Button.new()
	craft_core.text = "C: 2 осколка → искровое ядро"
	craft_core.pressed.connect(_craft_inventory_item.bind("spark_core"))
	column.add_child(craft_core)
	var craft_lantern: Button = Button.new()
	craft_lantern.text = "J: ядро + 2 эссенции → лесной фонарь"
	craft_lantern.pressed.connect(_craft_inventory_item.bind("forest_lantern"))
	column.add_child(craft_lantern)
	var craft_boots: Button = Button.new()
	craft_boots.text = "U: 1 осколок + 2 эссенции → сапоги следопыта"
	craft_boots.pressed.connect(_craft_inventory_item.bind("trail_boots"))
	column.add_child(craft_boots)
	var equip_boots: Button = Button.new()
	equip_boots.text = "Y: надеть / снять сапоги (+25% скорость)"
	equip_boots.pressed.connect(_toggle_trail_boots)
	column.add_child(equip_boots)
	inventory_feedback = Label.new()
	column.add_child(inventory_feedback)
	inventory_panel.visible = false
	_update_inventory_ui("", 0)


func _update_inventory_ui(_item_id: String = "", _new_count: int = 0) -> void:
	if not is_instance_valid(inventory_label) or not is_instance_valid(inventory):
		return
	var lines: PackedStringArray = PackedStringArray()
	for item_id in ItemCatalog.all_item_ids():
		var slot: String = ItemCatalog.equipment_slot(item_id)
		var worn: String = " [ЭКИП.]" if not slot.is_empty() and inventory.get_equipped_item(slot) == item_id else ""
		lines.append("%s: %d / %d%s" % [ItemCatalog.item_name(item_id),
			inventory.get_count(item_id), ItemCatalog.max_stack(item_id), worn])
	inventory_label.text = "\n".join(lines)


func _toggle_inventory_ui() -> void:
	if is_instance_valid(inventory_panel):
		inventory_panel.visible = not inventory_panel.visible
		if inventory_panel.visible:
			_update_inventory_ui()


func _craft_inventory_item(recipe_id: String) -> void:
	if not is_instance_valid(inventory):
		return
	var succeeded: bool = inventory.craft(recipe_id)
	if is_instance_valid(inventory_feedback):
		inventory_feedback.text = ("Создано: %s" % ItemCatalog.item_name(recipe_id)
			if succeeded else "Не хватает материалов или места")
	_update_inventory_ui()


func _build_equipped_lantern() -> void:
	# Crafted equipment has an immediate gameplay use: localized warm light.
	# Shadows are disabled here to avoid a second shadow-rendering cost.
	equipped_lantern = OmniLight3D.new()
	equipped_lantern.name = "CraftedForestLantern"
	equipped_lantern.light_color = Color(1.0, 0.72, 0.35)
	equipped_lantern.light_energy = 1.3
	equipped_lantern.omni_range = 10.0
	equipped_lantern.shadow_enabled = false
	equipped_lantern.position = Vector3(0.4, -0.4, -0.8)
	player_character.get_view_camera().add_child(equipped_lantern)
	equipped_lantern.visible = false


func _toggle_equipped_lantern() -> void:
	if not is_instance_valid(equipped_lantern):
		return
	if inventory.get_equipped_item("utility") != "forest_lantern":
		if not inventory.equip_item("forest_lantern"):
			if is_instance_valid(inventory_feedback):
				inventory_feedback.text = "Сначала создайте лесной фонарь"
			return
	equipped_lantern.visible = not equipped_lantern.visible
	if is_instance_valid(inventory_feedback):
		inventory_feedback.text = ("Лесной фонарь: ВКЛ" if equipped_lantern.visible
			else "Лесной фонарь: ВЫКЛ")


func _on_equipment_changed(slot: String, item_id: String) -> void:
	if is_instance_valid(player_attributes):
		if item_id.is_empty():
			player_attributes.remove_equipment(slot)
		else:
			player_attributes.set_equipment(slot, ItemCatalog.equipment_modifiers(item_id))
	if slot == "utility" and item_id != "forest_lantern" and is_instance_valid(equipped_lantern):
		equipped_lantern.visible = false
	_update_inventory_ui()


func _toggle_trail_boots() -> void:
	if inventory.get_equipped_item("feet") == "trail_boots":
		inventory.unequip_slot("feet")
	elif not inventory.equip_item("trail_boots"):
		if is_instance_valid(inventory_feedback):
			inventory_feedback.text = "Сначала создайте сапоги следопыта"


func _activate_player_ability(ability_id: String) -> void:
	if not is_instance_valid(player_abilities) or player_character.is_flying:
		return
	var success: bool = player_abilities.activate(ability_id)
	if is_instance_valid(inventory_feedback):
		inventory_feedback.text = ("Способность: %s" % ability_id if success
			else "Недостаточно выносливости или идёт перезарядка")


func _build_combat_ui() -> void:
	var ui: CanvasLayer = get_node("VisualQualityUI") as CanvasLayer
	combat_label = Label.new()
	combat_label.name = "WorldCombatFeedback"
	combat_label.anchor_top = 1.0
	combat_label.anchor_bottom = 1.0
	combat_label.offset_left = 18.0
	combat_label.offset_right = 690.0
	combat_label.offset_top = -60.0
	combat_label.offset_bottom = -16.0
	combat_label.add_theme_font_size_override("font_size", 17)
	combat_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.58))
	ui.add_child(combat_label)
	_on_combat_message("M: удар | N: оглушающий импульс | Backspace: возродиться")


func _on_combat_message(message: String) -> void:
	if is_instance_valid(combat_label):
		combat_label.text = message


func _on_sentry_defeated(_coord: Vector2i) -> void:
	sentries_defeated += 1
	_on_combat_message("Страж повержен! Лесная эссенция добавлена в инвентарь")


func _on_player_defeated() -> void:
	_on_combat_message("Вы потерпели поражение. Backspace: возродиться")


func _respawn_player() -> void:
	if not is_instance_valid(player_combatant) or player_combatant.is_alive():
		return
	player_character.global_position = Vector3(0.0, 0.5, 0.0)
	player_character.velocity = Vector3.ZERO
	player_combatant.restore_health(player_attributes.get_stat("max_health"))
	player_attributes.set_stamina(player_attributes.get_stat("max_stamina"))
	_on_combat_message("Вы восстановили здоровье. Стражи остаются в мире")


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
