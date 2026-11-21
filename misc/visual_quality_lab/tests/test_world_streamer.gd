extends SceneTree

const Streamer = preload("res://addons/visual_quality/world_streamer.gd")


func _initialize() -> void:
	assert(Streamer.cell_at_local_position(Vector3.ZERO, 14.0) == Vector2i.ZERO)
	assert(Streamer.cell_at_local_position(Vector3(14.0, 3.0, 28.0), 14.0) == Vector2i(1, 2))
	assert(Streamer.cell_at_local_position(Vector3(-0.1, 0.0, -14.0), 14.0) == Vector2i(-1, -1))
	assert(Streamer.cell_at_local_position(Vector3(14.0, 0.0, 0.0), 0.0) == Vector2i.ZERO)
	assert(Streamer.within_cell_radius(Vector2i(2, 2), Vector2i.ZERO, 2))
	assert(not Streamer.within_cell_radius(Vector2i(3, 0), Vector2i.ZERO, 2))
	assert(not Streamer.within_cell_radius(Vector2i.ZERO, Vector2i.ZERO, -1))
	var manager = Streamer.new()
	manager.streaming_enabled = false
	manager.set_quality_profile(0)
	assert(manager.load_radius_cells == 1 and manager.unload_radius_cells == 2)
	manager.set_quality_profile(1)
	assert(manager.load_radius_cells == 2 and manager.unload_radius_cells == 3)
	manager.set_quality_profile(2)
	assert(manager.load_radius_cells == 3 and manager.unload_radius_cells == 4)
	manager.register_scene_cell(Vector2i(1, 2), "res://world/forest_cell.tscn")
	assert(manager.registered_cell_count() == 1)
	manager.unregister_scene_cell(Vector2i(1, 2))
	assert(manager.registered_cell_count() == 0)
	manager.free()
	print("WorldStreamer3D: 13 unit checks passed")
	quit(0)
