extends SceneTree

const Streamer = preload("res://addons/visual_quality/world_streamer.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var stage: Node3D = Node3D.new()
	root.add_child(stage)
	var source: Node3D = Node3D.new()
	source.name = "StreamingSource"
	stage.add_child(source)
	var manager = Streamer.new()
	manager.streaming_enabled = false
	manager.source = source
	manager.cell_size = 14.0
	manager.load_radius_cells = 0
	manager.unload_radius_cells = 1
	manager.max_spawns_per_update = 1
	manager.register_scene_cell(Vector2i.ZERO, "res://world/forest_cell.tscn")
	manager.register_scene_cell(Vector2i(1, 0), "res://world/forest_cell.tscn")
	stage.add_child(manager)
	manager.streaming_enabled = true
	var loaded: bool = false
	for i in range(300):
		manager.refresh_now()
		if manager.active_cell_count() > 0:
			loaded = true
			break
		await create_timer(0.01).timeout
	assert(loaded, "The player cell must stream in from the threaded PackedScene")
	assert(manager.active_cell_count() == 1, "Spawn budget and radius must be enforced")
	assert(manager.get_active_cell(Vector2i.ZERO) != null)
	assert(manager.get_active_cell(Vector2i.ZERO).has_method("set_quality"))
	manager.get_active_cell(Vector2i.ZERO).call("set_quality", 0)
	# Moving beyond the unload radius must reclaim the old Node3D.
	source.position = Vector3(56, 0, 0)
	manager.refresh_now()
	assert(manager.active_cell_count() == 0)
	assert(manager.get_active_cell(Vector2i.ZERO) == null)
	stage.queue_free()
	print("WorldStreamer3D: 6 live scene streaming assertions passed")
	quit(0)
