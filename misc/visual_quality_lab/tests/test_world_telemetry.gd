extends SceneTree

const Telemetry = preload("res://addons/visual_quality/world_telemetry.gd")


func _initialize() -> void:
	var empty: Array[float] = []
	assert(Telemetry.percentile_nearest_rank(empty, 0.95) == 0.0)
	var values: Array[float] = [1.0, 2.0, 8.0, 3.0, 4.0]
	assert(Telemetry.percentile_nearest_rank(values, 0.95) == 8.0)
	assert(Telemetry.percentile_nearest_rank(values, 0.5) == 3.0)
	assert(Telemetry.percentile_nearest_rank(values, -1.0) == 1.0)
	assert(Telemetry.percentile_nearest_rank(values, 5.0) == 8.0)
	var monitor = Telemetry.new()
	monitor.capacity = 3
	for n in range(5):
		monitor.push_snapshot({"elapsed_ms": n, "cpu_ms": float(n + 1)})
	assert(monitor.sample_count() == 3)
	assert(monitor.get_latest()["elapsed_ms"] == 4)
	var recent: Array[Dictionary] = monitor.get_samples_oldest_first()
	assert(recent[0]["elapsed_ms"] == 2)
	assert(recent[2]["elapsed_ms"] == 4)
	assert(monitor.get_cpu_p95_ms() == 5.0)
	var latest: Dictionary = monitor.get_latest()
	latest["cpu_ms"] = 10000.0
	assert(monitor.get_latest()["cpu_ms"] == 5.0, "Snapshots are defensive copies")
	monitor.csv_path = "/tmp/unsafe.csv"
	assert(monitor.export_csv() == ERR_INVALID_PARAMETER)
	monitor.csv_path = "user://world_telemetry_unit_test.csv"
	assert(monitor.export_csv() == OK)
	var file: FileAccess = FileAccess.open(monitor.csv_path, FileAccess.READ)
	assert(file != null)
	assert(file.get_line().begins_with("elapsed_ms,fps,process_ms"))
	assert(file.get_length() > 100)
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(monitor.csv_path))
	monitor.clear()
	assert(monitor.sample_count() == 0)
	monitor.free()
	print("WorldTelemetry3D: 17 checks passed")
	quit(0)
