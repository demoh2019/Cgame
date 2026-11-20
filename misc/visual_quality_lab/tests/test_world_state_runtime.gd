extends SceneTree

const Streamer = preload("res://addons/visual_quality/world_streamer.gd")
const Store = preload("res://addons/visual_quality/world_state_store.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var save_path: String = "user://visual_lab_state_runtime_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	var stage: Node3D = Node3D.new()
	root.add_child(stage)
	var player: Node3D = Node3D.new()
	stage.add_child(player)
	var streamer = Streamer.new()
	streamer.streaming_enabled = false
	streamer.source = player
	streamer.cell_size = 14.0
	streamer.load_radius_cells = 0
	streamer.unload_radius_cells = 1
	streamer.register_scene_cell(Vector2i.ZERO, "res://world/forest_cell.tscn")
	var store = Store.new()
	store.world_id = "streamed_beacon_unit_world"
	store.save_path = save_path
	store.streamer = streamer
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
	assert(loaded, "Forest cell must load before activation")
	var first: Node3D = streamer.get_active_cell(Vector2i.ZERO)
	assert(first != null)
	assert(not first.beacon_activated)
	assert(first.try_activate_beacon(first.get_beacon_world_position(), 0.4))
	assert(first.beacon_activated)
	assert(store.saved_cell_count() == 1)
	assert(FileAccess.file_exists(save_path), "Activation must persist immediately")
	assert(not first.try_activate_beacon(first.get_beacon_world_position(), 0.4), "Cannot activate the same beacon twice")

	# Unload by moving the streaming source. The unload event must see a live cell.
	player.position = Vector3(84.0, 0, 0)
	streamer.refresh_now()
	assert(streamer.active_cell_count() == 0)
	assert(store.get_saved_state(Vector2i.ZERO).get("activated", false))
	player.position = Vector3.ZERO
	loaded = false
	for i in range(300):
		streamer.refresh_now()
		if streamer.active_cell_count() == 1:
			loaded = true
			break
		await create_timer(0.01).timeout
	assert(loaded)
	var again: Node3D = streamer.get_active_cell(Vector2i.ZERO)
	assert(again != first, "Fresh Node3D must have been instantiated")
	assert(again.beacon_activated, "Activation must survive scene unload/reload")

	var disk_reader = Store.new()
	disk_reader.save_path = save_path
	disk_reader.world_id = store.world_id
	disk_reader.save_on_exit = false
	assert(disk_reader.load_from_disk())
	assert(disk_reader.get_saved_state(Vector2i.ZERO)["activated"] == true)
	store.clear_all_states()
	assert(store.saved_cell_count() == 0)
	assert(not again.beacon_activated)
	assert(not disk_reader.get_saved_state(Vector2i.ZERO).is_empty()) # Prior reader was a snapshot.
	var clean_reader = Store.new()
	clean_reader.save_path = save_path
	clean_reader.world_id = store.world_id
	clean_reader.save_on_exit = false
	assert(clean_reader.load_from_disk())
	assert(clean_reader.saved_cell_count() == 0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	streamer.streaming_enabled = false
	stage.queue_free()
	disk_reader.free()
	clean_reader.free()
	print("WorldStateStore3D: 18 integration assertions passed")
	quit(0)
