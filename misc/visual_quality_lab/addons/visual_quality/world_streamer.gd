extends Node3D
class_name WorldStreamer3D
## Reusable, scene-based world streaming for Godot 4. Loads PackedScene assets
## asynchronously; instantiates scene-tree nodes only on the main thread.
## This is spatial scene streaming, not Unreal's editor World Partition/HLOD.

signal cell_loaded(coord: Vector2i, instance: Node3D)
signal cell_unloaded(coord: Vector2i)
signal asset_load_failed(path: String, error: int)

@export_range(4.0, 256.0, 1.0) var cell_size: float = 14.0
@export_range(0, 8, 1) var load_radius_cells: int = 2
@export_range(1, 10, 1) var unload_radius_cells: int = 3
@export_range(0.05, 2.0, 0.05) var update_interval_seconds: float = 0.15
@export_range(1, 8, 1) var max_spawns_per_update: int = 2
@export_range(1, 16, 1) var max_unloads_per_update: int = 4
@export_range(1, 8, 1) var max_concurrent_loads: int = 2
@export var streaming_enabled: bool = true

var source: Node3D
var _definitions: Dictionary = {}  # Vector2i -> resource path
var _active: Dictionary = {}       # Vector2i -> Node3D
var _scene_cache: Dictionary = {}  # String -> PackedScene
var _pending_paths: Dictionary = {} # String -> true
var _failed_paths: Dictionary = {} # String -> Error
var _elapsed: float = 0.0


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
	_poll_background_loads()
	var center: Vector2i = cell_at_local_position(to_local(source.global_position), cell_size)
	# Unload outside a larger radius to avoid jitter at load boundaries.
	var unload_budget: int = max_unloads_per_update
	for coord in _active.keys():
		if unload_budget <= 0:
			break
		if not _definitions.has(coord) or not within_cell_radius(coord, center, unload_radius_cells):
			_unload_cell(coord)
			unload_budget -= 1
	var wanted: Array[Vector2i] = []
	for coord in _definitions.keys():
		if within_cell_radius(coord, center, load_radius_cells) and not _active.has(coord):
			wanted.append(coord)
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ad: int = (a - center).length_squared()
		var bd: int = (b - center).length_squared()
		if ad == bd:
			if a.x != b.x:
				return a.x < b.x
			return a.y < b.y
		return ad < bd
	)
	var spawn_budget: int = max_spawns_per_update
	for coord in wanted:
		if spawn_budget <= 0:
			break
		var path: String = _definitions[coord]
		if _scene_cache.has(path):
			if _spawn_cell(coord, _scene_cache[path]):
				spawn_budget -= 1
		elif not _pending_paths.has(path) and not _failed_paths.has(path):
			if _pending_paths.size() < max_concurrent_loads:
				_request_asset(path)


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
	return true


func _unload_cell(coord: Vector2i) -> void:
	if not _active.has(coord):
		return
	var instance: Node3D = _active[coord]
	_active.erase(coord)
	if is_instance_valid(instance):
		remove_child(instance)
		instance.queue_free()
	cell_unloaded.emit(coord)


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
