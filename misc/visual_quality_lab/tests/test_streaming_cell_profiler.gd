extends SceneTree

const Streamer = preload("res://addons/visual_quality/world_streamer.gd")
const Inspector = preload("res://addons/visual_quality/world_streaming_inspector.gd")


func _initialize() -> void:
	var streaming = Streamer.new()
	streaming.max_profiled_cells = 2
	streaming._record_cell_timing(Vector2i.ZERO, true, 120)
	streaming._record_cell_timing(Vector2i.ZERO, true, 90)
	streaming._record_cell_timing(Vector2i.ZERO, false, 20)
	assert(streaming.get_cell_profile(Vector2i.ZERO)["peak_spawn_us"] == 120)
	assert(streaming.get_cell_profile(Vector2i.ZERO)["last_spawn_us"] == 90)
	assert(streaming.get_cell_profile(Vector2i.ZERO)["spawn_count"] == 2)
	assert(streaming.get_cell_profile(Vector2i.ZERO)["unload_count"] == 1)
	var copy: Dictionary = streaming.get_cell_profile(Vector2i.ZERO)
	copy["peak_spawn_us"] = 999
	assert(streaming.get_cell_profile(Vector2i.ZERO)["peak_spawn_us"] == 120)
	streaming._record_cell_timing(Vector2i(1, 0), true, 250)
	assert(streaming.get_slowest_cells(1)[0]["coord"] == Vector2i(1, 0))
	assert(streaming.get_slowest_cells(0).is_empty())
	streaming._record_cell_timing(Vector2i(2, 0), true, 400)
	assert(streaming.profiled_cell_count() == 2)
	assert(streaming.get_cell_profile(Vector2i.ZERO).is_empty(), "Oldest profile must evict")
	assert(streaming.get_slowest_cells(2)[0]["coord"] == Vector2i(2, 0))
	var inspector = Inspector.new()
	inspector.streamer = streaming
	inspector.hotspot_csv_path = "/tmp/unsafe.csv"
	assert(inspector.export_hotspot_csv() == ERR_INVALID_PARAMETER)
	inspector.hotspot_csv_path = "user://visual_lab_cell_profiler_test.csv"
	assert(inspector.export_hotspot_csv() == OK)
	var file: FileAccess = FileAccess.open(inspector.hotspot_csv_path, FileAccess.READ)
	assert(file != null)
	assert(file.get_line().begins_with("cell_x,cell_z,spawns,unloads"))
	assert(file.get_line().begins_with("2,0,1,0,400"))
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(inspector.hotspot_csv_path))
	inspector.free()
	streaming.free()
	print("World streaming per-cell profiler: 17 cases passed")
	quit(0)
