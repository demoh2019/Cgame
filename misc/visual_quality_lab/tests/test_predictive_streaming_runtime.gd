extends SceneTree

const Streamer = preload("res://addons/visual_quality/world_streamer.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var stage: Node3D = Node3D.new()
	root.add_child(stage)
	var source: CharacterBody3D = CharacterBody3D.new()
	source.position = Vector3(1, 0, 1)
	source.velocity = Vector3(28, 0, 0)
	stage.add_child(source)
	var streaming = Streamer.new()
	streaming.streaming_enabled = false
	streaming.source = source
	streaming.load_radius_cells = 0
	streaming.unload_radius_cells = 2
	streaming.prefetch_radius_cells = 0
	streaming.max_prefetch_cells = 1
	streaming.lookahead_seconds = 0.8
	streaming.max_spawns_per_update = 2
	streaming.register_scene_cell(Vector2i.ZERO, "res://world/forest_cell.tscn")
	streaming.register_scene_cell(Vector2i(1, 0), "res://world/forest_cell.tscn")
	stage.add_child(streaming)
	streaming.streaming_enabled = true
	var loaded: bool = false
	for i in range(400):
		streaming.refresh_now()
		if streaming.active_cell_count() == 2:
			loaded = true
			break
		await create_timer(0.01).timeout
	assert(loaded, "Current and predicted cells must become active")
	assert(streaming.last_predicted_cell == Vector2i(1, 0))
	assert(streaming.total_prefetched_count >= 1)
	assert(streaming.profiled_cell_count() == 2)
	assert(streaming.get_cell_profile(Vector2i.ZERO)["spawn_count"] == 1)
	assert(streaming.get_cell_profile(Vector2i(1, 0))["spawn_count"] == 1)
	assert(streaming.get_slowest_cells(2).size() == 2)
	source.velocity = Vector3.ZERO
	source.position = Vector3(-85, 0, 1)
	streaming.refresh_now()
	assert(streaming.active_cell_count() == 0)
	assert(streaming.get_cell_profile(Vector2i.ZERO)["unload_count"] == 1)
	stage.queue_free()
	print("Predictive streaming: runtime prefetch and per-cell timings passed")
	quit(0)
