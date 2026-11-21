extends SceneTree

const Streamer = preload("res://addons/visual_quality/world_streamer.gd")
const StateStore = preload("res://addons/visual_quality/world_state_store.gd")
const Attributes = preload("res://addons/visual_quality/attribute_component.gd")
const Combatant = preload("res://addons/visual_quality/combat_component.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var filepath: String = "user://v17_combat_streaming_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(filepath))
	var stage = Node3D.new()
	root.add_child(stage)
	var player = CharacterBody3D.new()
	stage.add_child(player)
	var attributes = Attributes.new()
	player.add_child(attributes)
	var combatant = Combatant.new()
	combatant.name = "PlayerCombatant"
	combatant.team_id = Combatant.TEAM_PLAYER
	combatant.attributes = attributes
	player.add_child(combatant)
	var streamer = Streamer.new()
	streamer.source = player
	streamer.streaming_enabled = false
	streamer.load_radius_cells = 0
	streamer.unload_radius_cells = 1
	streamer.register_scene_cell(Vector2i.ZERO, "res://world/forest_cell.tscn")
	var store = StateStore.new()
	store.streamer = streamer
	store.save_path = filepath
	store.world_id = "v17_sentry_test"
	store.save_on_exit = false
	stage.add_child(store)
	stage.add_child(streamer)
	streamer.streaming_enabled = true
	var loaded: bool = false
	for i in range(300):
		streamer.refresh_now()
		if streamer.active_cell_count() == 1:
			loaded = true
			break
		await create_timer(0.01).timeout
	assert(loaded)
	var old: Node3D = streamer.get_active_cell(Vector2i.ZERO)
	var sentry: Node3D = old.get_hostile_sentry()
	assert(sentry.combatant.is_alive())
	var rewards: Array[String] = []
	old.resource_awarded.connect(func(item_id: String, uid: String) -> void:
		if item_id == "forest_essence":
			rewards.append(uid)
	)
	for i in range(4):
		sentry.combatant._physics_process(1.0)
		sentry.combatant.receive_damage(36.0, Combatant.TEAM_PLAYER)
	assert(not sentry.combatant.is_alive())
	assert(rewards.has("sentry:0:0"))
	assert(rewards.size() == 1)
	assert(store.get_saved_state(Vector2i.ZERO).get("sentry_health", 999.0) == 0.0)
	player.position = Vector3(84.0, 0, 0)
	streamer.refresh_now()
	assert(streamer.active_cell_count() == 0)
	player.position = Vector3.ZERO
	loaded = false
	for i in range(300):
		streamer.refresh_now()
		if streamer.active_cell_count() == 1:
			loaded = true
			break
		await create_timer(0.01).timeout
	assert(loaded)
	var new_cell: Node3D = streamer.get_active_cell(Vector2i.ZERO)
	assert(new_cell != old)
	var corpse: Node3D = new_cell.get_hostile_sentry()
	assert(not corpse.combatant.is_alive())
	assert(corpse.collision_layer == 0)
	store.clear_all_states()
	assert(corpse.combatant.is_alive())
	streamer.streaming_enabled = false
	stage.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(filepath))
	print("World combat streaming: defeat/reward/persistence/reset passed")
	quit(0)
