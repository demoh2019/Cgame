extends Node3D
class_name WorldStreamer3D

const StreamingPlanner = preload("res://addons/visual_quality/world_streaming_planner.gd")
## Reusable, scene-based world streaming for Godot 4. Loads PackedScene assets
## asynchronously; instantiates scene-tree nodes only on the main thread.
## This is spatial scene streaming, not Unreal's editor World Partition/HLOD.

signal cell_loaded(coord: Vector2i, instance: Node3D)
signal cell_unloaded(coord: Vector2i)
signal cell_about_to_unload(coord: Vector2i, instance: Node3D)
signal asset_load_failed(path: String, error: int)

@export_range(4.0, 256.0, 1.0) var cell_size: float = 14.0
@export_range(0, 8, 1) var load_radius_cells: int = 2
@export_range(1, 10, 1) var unload_radius_cells: int = 3
@export_range(0.05, 2.0, 0.05) var update_interval_seconds: float = 0.15
@export_range(1, 8, 1) var max_spawns_per_update: int = 2
@export_range(100, 10000, 100) var max_spawn_time_usec_per_update: int = 2500
@export_range(1, 16, 1) var max_unloads_per_update: int = 4
@export_range(1, 8, 1) var max_concurrent_loads: int = 2
@export_range(0.0, 3.0, 0.05) var lookahead_seconds: float = 0.8
@export_range(0, 4, 1) var max_lookahead_cells: int = 2
@export_range(0, 3, 1) var prefetch_radius_cells: int = 1
@export_range(0, 16, 1) var max_prefetch_cells: int = 4
@export_range(8, 512, 1) var max_profiled_cells: int = 96
@export var streaming_enabled: bool = true

var source: Node3D
var _definitions: Dictionary = {}  # Vector2i -> resource path
var _active: Dictionary = {}       # Vector2i -> Node3D
var _scene_cache: Dictionary = {}  # String -> PackedScene
var _pending_paths: Dictionary = {} # String -> true
var _failed_paths: Dictionary = {} # String -> Error
var _elapsed: float = 0.0
var last_update_micros: int = 0
var peak_update_micros: int = 0
var last_spawned_count: int = 0
var last_unloaded_count: int = 0
var total_spawned_count: int = 0
var total_unloaded_count: int = 0
var last_prefetched_count: int = 0
var total_prefetched_count: int = 0
var last_predicted_cell: Vector2i = Vector2i.ZERO
var _cell_profiles: Dictionary = {}  # Vector2i -> bounded timing + operation counts


func _process(delta: float) -> void:
	if not streaming_enabled or source == null or not is_instance_valid(source):
		return
	_elapsed += maxf(delta, 0.0)
	if _elapsed >= update_interval_seconds:
		_elapsed = 0.0
		refresh_now()


func register_scene_cell(coord: Vector2i, path: String) -> void:
	if not path.begins_with("res://"):
		push_warning("WorldStreamer3D: expected a res:// PackedScene path: %s" % path)
		return
	_definitions[coord] = path


func unregister_scene_cell(coord: Vector2i) -> void:
	_definitions.erase(coord)
	_unload_cell(coord)


func clear_failed_asset(path: String) -> void:
	_failed_paths.erase(path)


func refresh_now() -> void:
	if not streaming_enabled or source == null or not is_instance_valid(source):
		return
	var started_usec: int = Time.get_ticks_usec()
	last_spawned_count = 0
	last_unloaded_count = 0
	_poll_background_loads()
	var local_source: Vector3 = to_local(source.global_position)
	var center: Vector2i = cell_at_local_position(local_source, cell_size)
	var velocity_local: Vector3 = Vector3.ZERO
	if source is CharacterBody3D:
		# CharacterBody3D.velocity is in world coordinates; convert to the
		# streamer's local axes so rotated worlds prefetch correctly.
		velocity_local = global_basis.inverse() * (source as CharacterBody3D).velocity
	last_predicted_cell = StreamingPlanner.predict_cell(local_source, velocity_local,
		cell_size, lookahead_seconds, max_lookahead_cells)
	last_prefetched_count = 0
	# Unload outside a larger radius to avoid jitter at load boundaries.
	var unload_budget: int = max_unloads_per_update
	for coord in _active.keys():
		if unload_budget <= 0:
			break
		if not _definitions.has(coord) or not within_cell_radius(coord, center, unload_radius_cells):
			_unload_cell(coord)
			unload_budget -= 1
	var wanted: Array[Vector2i] = StreamingPlanner.build_load_queue(
		_definitions, _active, center, last_predicted_cell,
		load_radius_cells, unload_radius_cells, prefetch_radius_cells,
		max_prefetch_cells)
	var spawn_budget: int = max_spawns_per_update
	var spawn_started_usec: int = Time.get_ticks_usec()
	for coord in wanted:
		# Cooperative budget: cannot interrupt a single PackedScene.instantiate(),
		# but can stop before attempting the next one.
		if spawn_budget <= 0 or Time.get_ticks_usec() - spawn_started_usec >= max_spawn_time_usec_per_update:
			break
		var path: String = _definitions[coord]
		if _scene_cache.has(path):
			if _spawn_cell(coord, _scene_cache[path]):
				spawn_budget -= 1
				last_spawned_count += 1
				total_spawned_count += 1
				if StreamingPlanner.is_speculative(coord, center, load_radius_cells):
					last_prefetched_count += 1
					total_prefetched_count += 1
		elif not _pending_paths.has(path) and not _failed_paths.has(path):
			if _pending_paths.size() < max_concurrent_loads:
				_request_asset(path)
	last_update_micros = Time.get_ticks_usec() - started_usec
	peak_update_micros = maxi(peak_update_micros, last_update_micros)


func _request_asset(path: String) -> void:
	if not ResourceLoader.exists(path, "PackedScene"):
		_record_failure(path, ERR_FILE_NOT_FOUND)
		return
	var result: Error = ResourceLoader.load_threaded_request(path, "PackedScene")
	if result == OK:
		_pending_paths[path] = true
	else:
		_record_failure(path, result)


func _poll_background_loads() -> void:
	for path in _pending_paths.keys():
		var status: int = ResourceLoader.load_threaded_get_status(path)
		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				# load_threaded_get() is only invoked once status reports LOADED;
				# never block the main thread waiting for a scene asset.
				var resource: Resource = ResourceLoader.load_threaded_get(path)
				_pending_paths.erase(path)
				if resource is PackedScene:
					_scene_cache[path] = resource
				else:
					_record_failure(path, ERR_FILE_UNRECOGNIZED)
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_pending_paths.erase(path)
				_record_failure(path, ERR_CANT_OPEN)


func _spawn_cell(coord: Vector2i, packed: PackedScene) -> bool:
	var started_usec: int = Time.get_ticks_usec()
	var instance: Node = packed.instantiate()
	if not instance is Node3D:
		if instance != null:
			instance.free()
		_record_failure(_definitions[coord], ERR_INVALID_DATA)
		return false
	var node: Node3D = instance as Node3D
	node.name = "Cell_%d_%d" % [coord.x, coord.y]
	node.position = Vector3(float(coord.x) * cell_size, 0.0, float(coord.y) * cell_size)
	if node.has_method("configure_stream_cell"):
		node.call("configure_stream_cell", coord)
	add_child(node)
	_active[coord] = node
	cell_loaded.emit(coord, node)
	_record_cell_timing(coord, true, Time.get_ticks_usec() - started_usec)
	return true


func _unload_cell(coord: Vector2i) -> void:
	if not _active.has(coord):
		return
	var started_usec: int = Time.get_ticks_usec()
	var instance: Node3D = _active[coord]
	# Let persistence and gameplay systems snapshot the live instance first.
	cell_about_to_unload.emit(coord, instance)
	_active.erase(coord)
	if is_instance_valid(instance):
		remove_child(instance)
		instance.queue_free()
	cell_unloaded.emit(coord)
	last_unloaded_count += 1
	total_unloaded_count += 1
	_record_cell_timing(coord, false, Time.get_ticks_usec() - started_usec)


func _record_cell_timing(coord: Vector2i, spawned: bool, microseconds: int) -> void:
	if not _cell_profiles.has(coord) and _cell_profiles.size() >= max_profiled_cells:
		# Bounded diagnostic cache: preserve the currently observed cells and
		# evict the oldest *record*, never the actual streamed scene.
		_cell_profiles.erase(_cell_profiles.keys()[0])
	var entry: Dictionary = _cell_profiles.get(coord, {
		"spawn_count": 0, "unload_count": 0, "last_spawn_us": 0,
		"peak_spawn_us": 0, "last_unload_us": 0
	})
	if spawned:
		entry["spawn_count"] = int(entry["spawn_count"]) + 1
		entry["last_spawn_us"] = microseconds
		entry["peak_spawn_us"] = maxi(int(entry["peak_spawn_us"]), microseconds)
	else:
		entry["unload_count"] = int(entry["unload_count"]) + 1
		entry["last_unload_us"] = microseconds
	# Reinsert to provide oldest-first bounded eviction.
	_cell_profiles.erase(coord)
	_cell_profiles[coord] = entry


func get_cell_profile(coord: Vector2i) -> Dictionary:
	return _cell_profiles.get(coord, {}).duplicate(true)


func profiled_cell_count() -> int:
	return _cell_profiles.size()


func get_slowest_cells(limit: int = 5) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for coord in _cell_profiles.keys():
		var entry: Dictionary = _cell_profiles[coord].duplicate(true)
		entry["coord"] = coord
		if int(entry.get("spawn_count", 0)) > 0:
			entries.append(entry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var at: int = int(a.get("peak_spawn_us", 0))
		var bt: int = int(b.get("peak_spawn_us", 0))
		if at != bt:
			return at > bt
		return StreamingPlanner.less_coord(a["coord"], b["coord"])
	)
	var result: Array[Dictionary] = []
	for i in range(mini(maxi(limit, 0), entries.size())):
		result.append(entries[i])
	return result


func _record_failure(path: String, code: int) -> void:
	_failed_paths[path] = code
	asset_load_failed.emit(path, code)
	push_warning("WorldStreamer3D: failed to load '%s' (error %d)" % [path, code])


func active_cell_count() -> int:
	return _active.size()


func registered_cell_count() -> int:
	return _definitions.size()


func pending_asset_count() -> int:
	return _pending_paths.size()


func is_cell_registered(coord: Vector2i) -> bool:
	return _definitions.has(coord)


func get_active_cell(coord: Vector2i) -> Node3D:
	if _active.has(coord):
		return _active[coord]
	return null


func get_active_cells() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node in _active.values():
		result.append(node)
	return result


func set_quality_profile(profile: int) -> void:
	match clampi(profile, 0, 2):
		0:
			load_radius_cells = 1
			unload_radius_cells = 2
		1:
			load_radius_cells = 2
			unload_radius_cells = 3
		2:
			load_radius_cells = 3
			unload_radius_cells = 4
	refresh_now()


static func cell_at_local_position(local_pos: Vector3, width: float) -> Vector2i:
	if not is_finite(width) or width <= 0.0:
		return Vector2i.ZERO
	return Vector2i(floori(local_pos.x / width), floori(local_pos.z / width))


static func within_cell_radius(coord: Vector2i, center: Vector2i, radius: int) -> bool:
	if radius < 0:
		return false
	return maxi(absi(coord.x - center.x), absi(coord.y - center.y)) <= radius
