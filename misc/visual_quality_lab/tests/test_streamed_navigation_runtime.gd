extends SceneTree

const Streamer = preload("res://addons/visual_quality/world_streamer.gd")
const Store = preload("res://addons/visual_quality/world_state_store.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var save_path: String = "user://v10_streamed_npc_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	var stage: Node3D = Node3D.new()
	root.add_child(stage)
	var source: Node3D = Node3D.new()
	stage.add_child(source)
	var streamer = Streamer.new()
	streamer.source = source
	streamer.streaming_enabled = false
	streamer.load_radius_cells = 0
	streamer.unload_radius_cells = 1
	streamer.register_scene_cell(Vector2i.ZERO, "res://world/forest_cell.tscn")
	var store = Store.new()
	store.world_id = "v10_navigation_test"
	store.save_path = save_path
	store.streamer = streamer
	store.save_on_exit = false
	stage.add_child(store)
	stage.add_child(streamer)
	streamer.streaming_enabled = true
	var loaded: bool = false
	for i in range(300):
		streamer.refresh_now()
		if streamer.active_cell_count() > 0:
			loaded = true
			break
		await create_timer(0.01).timeout
	assert(loaded, "Test cell must load")
	var first: Node3D = streamer.get_active_cell(Vector2i.ZERO)
	assert(first.get_node("NavigationTile") is NavigationRegion3D)
	assert(first.get_node("NavigationTile").navigation_mesh.get_polygon_count() == 1)
	var npc: Node3D = first.get_active_npc()
	assert(npc is CharacterBody3D)
	assert(npc.navigation_agent is NavigationAgent3D)
	assert(not npc.navigation_agent.avoidance_enabled)
	streamer.streaming_enabled = false
	npc.position = Vector3(1.0, 0.0, 2.0)
	npc.patrol_index = 2
	source.position = Vector3(90.0, 0.0, 0.0)
	streamer.streaming_enabled = true
	streamer.refresh_now()
	assert(streamer.active_cell_count() == 0)
	assert(store.get_saved_state(Vector2i.ZERO).get("npc_patrol", -1) == 2)
	var restored_position: Vector3 = store.get_saved_state(Vector2i.ZERO)["npc_position"]
	assert(is_equal_approx(restored_position.x, 1.0))
	source.position = Vector3.ZERO
	loaded = false
	for i in range(300):
		streamer.refresh_now()
		if streamer.active_cell_count() > 0:
			loaded = true
			break
		await create_timer(0.01).timeout
	assert(loaded)
	var second: Node3D = streamer.get_active_cell(Vector2i.ZERO)
	assert(second != first)
	var restored_npc: Node3D = second.get_active_npc()
	assert(restored_npc.patrol_index == 2)
	assert(is_equal_approx(restored_npc.position.x, 1.0))
	assert(is_equal_approx(restored_npc.position.z, 2.0))
	streamer.streaming_enabled = false
	stage.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("StreamedNavigation: 12 streaming and NPC persistence checks passed")
	quit(0)
