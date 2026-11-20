extends Node
class_name WorldTelemetry3D
## Lightweight, bounded performance recorder for the open-world demo.
## Uses engine CPU monitors; it does not claim these are GPU frame timings.

signal snapshot_captured(snapshot: Dictionary)

@export_range(0.2, 5.0, 0.1) var sample_interval_seconds: float = 0.5
@export_range(16, 600, 1) var capacity: int = 240
@export var csv_path: String = "user://visual_quality_world_telemetry.csv"
@export var sampling_enabled: bool = true

var streamer: WorldStreamer3D
var ai_interest: WorldAIInterestManager3D
var _elapsed: float = 0.0
var _records: Array[Dictionary] = []
var _next_index: int = 0


func _process(delta: float) -> void:
	if not sampling_enabled or delta <= 0.0:
		return
	_elapsed += delta
	if _elapsed >= sample_interval_seconds:
		_elapsed = 0.0
		sample_now()


func sample_now() -> Dictionary:
	var process_ms: float = maxf(float(Performance.get_monitor(Performance.TIME_PROCESS)), 0.0) * 1000.0
	var physics_ms: float = maxf(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)), 0.0) * 1000.0
	var row: Dictionary = {
		"elapsed_ms": Time.get_ticks_msec(),
		"fps": float(Performance.get_monitor(Performance.TIME_FPS)),
		"process_ms": process_ms,
		"physics_ms": physics_ms,
		"cpu_ms": process_ms + physics_ms,
		"active_cells": 0,
		"pending_assets": 0,
		"streamer_us": 0,
		"spawned": 0,
		"unloaded": 0,
		"total_spawned": 0,
		"total_unloaded": 0,
		"total_prefetched": 0,
		"profiled_cells": 0,
		"hottest_cell_us": 0,
		"ai_us": 0,
		"sleeping_npcs": 0,
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT))
	}
	if is_instance_valid(streamer):
		row["active_cells"] = streamer.active_cell_count()
		row["pending_assets"] = streamer.pending_asset_count()
		row["streamer_us"] = streamer.last_update_micros
		row["spawned"] = streamer.last_spawned_count
		row["unloaded"] = streamer.last_unloaded_count
		row["total_spawned"] = streamer.total_spawned_count
		row["total_unloaded"] = streamer.total_unloaded_count
		row["total_prefetched"] = streamer.total_prefetched_count
		row["profiled_cells"] = streamer.profiled_cell_count()
		var hottest: Array[Dictionary] = streamer.get_slowest_cells(1)
		if not hottest.is_empty():
			row["hottest_cell_us"] = hottest[0]["peak_spawn_us"]
	if is_instance_valid(ai_interest):
		row["ai_us"] = ai_interest.last_update_micros
		row["sleeping_npcs"] = ai_interest.sleeping_npc_count()
	push_snapshot(row)
	return row


func push_snapshot(row: Dictionary) -> void:
	# Ring buffer has bounded memory use, independent of gameplay duration.
	var copy: Dictionary = row.duplicate(true)
	if _records.size() < capacity:
		_records.append(copy)
	else:
		_records[_next_index] = copy
	_next_index = (_next_index + 1) % capacity
	snapshot_captured.emit(copy.duplicate(true))


func sample_count() -> int:
	return _records.size()


func get_latest() -> Dictionary:
	if _records.is_empty():
		return {}
	return _records[(_next_index - 1 + _records.size()) % _records.size()].duplicate(true)


func get_samples_oldest_first() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var count: int = _records.size()
	var first: int = _next_index if count >= capacity else 0
	for i in range(count):
		out.append(_records[(first + i) % count].duplicate(true))
	return out


func get_cpu_p95_ms() -> float:
	var values: Array[float] = []
	for sample in _records:
		values.append(maxf(float(sample.get("cpu_ms", 0.0)), 0.0))
	return percentile_nearest_rank(values, 0.95)


func export_csv() -> Error:
	if not csv_path.begins_with("user://"):
		return ERR_INVALID_PARAMETER
	var file: FileAccess = FileAccess.open(csv_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var columns: PackedStringArray = PackedStringArray([
		"elapsed_ms", "fps", "process_ms", "physics_ms", "cpu_ms",
		"active_cells", "pending_assets", "streamer_us", "spawned",
		"unloaded", "total_spawned", "total_unloaded", "total_prefetched",
		"profiled_cells", "hottest_cell_us", "ai_us", "sleeping_npcs", "objects"
	])
	file.store_csv_line(columns)
	for item in get_samples_oldest_first():
		var fields: PackedStringArray = PackedStringArray()
		for name in columns:
			fields.append(str(item.get(name, 0)))
		file.store_csv_line(fields)
	file.close()
	return OK


func clear() -> void:
	_records.clear()
	_next_index = 0


static func percentile_nearest_rank(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted_values: Array[float] = []
	for number in values:
		sorted_values.append(number)
	sorted_values.sort()
	var rank: int = clampi(ceili(clampf(fraction, 0.0, 1.0) * sorted_values.size()) - 1,
		0, sorted_values.size() - 1)
	return sorted_values[rank]
