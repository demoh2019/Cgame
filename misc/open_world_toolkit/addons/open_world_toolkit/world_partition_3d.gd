extends Node3D
class_name OWWorldPartition3D
## Deterministic authored-cell streaming with load/unload hysteresis.
## Threaded mode requests PackedScene resources without blocking _process;
## instantiation remains on the main thread. A path used by many cells
## shares one pending request and is instantiated separately for each cell.

signal cell_loaded(coordinate: Vector2i, instance: Node3D)
signal cell_unloaded(coordinate: Vector2i)
signal cell_load_failed(coordinate: Vector2i, scene_path: String)

@export_range(1.0, 100000.0, 1.0) var cell_size: float = 256.0
@export_range(0, 16, 1) var load_radius: int = 1
@export_range(0, 24, 1) var unload_radius: int = 2
@export_range(0.1, 5.0, 0.1) var check_interval: float = 0.5
@export_range(1, 32, 1) var max_cells_per_update: int = 2
@export_range(1, 32, 1) var max_pending_requests: int = 4
@export var threaded_loading: bool = true
@export var viewer_path: NodePath
@export var cells: Array[OWWorldCell] = []

var _active: Dictionary = {} # Vector2i -> Node3D
var _pending_paths: Dictionary = {} # String -> Array[Vector2i]
var _elapsed: float = 0.0


func world_to_cell(world_point: Vector3) -> Vector2i:
	var local := to_local(world_point)
	var safe_size := maxf(cell_size, 1.0)
	return Vector2i(floori(local.x / safe_size), floori(local.z / safe_size))


func wanted_cells(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for z in range(center.y - maxi(radius, 0), center.y + maxi(radius, 0) + 1):
		for x in range(center.x - maxi(radius, 0), center.x + maxi(radius, 0) + 1):
			result.append(Vector2i(x, z))
	return result


func planned_cells(center: Vector2i) -> Array[OWWorldCell]:
	## Resolve duplicate authored coordinates deterministically and load nearest first.
	var result: Array[OWWorldCell] = []
	var seen := {}
	for entry in cells:
		if entry == null or entry.scene_path.is_empty() or seen.has(entry.coordinate):
			continue
		var delta := entry.coordinate - center
		if maxi(absi(delta.x), absi(delta.y)) > maxi(0, load_radius):
			continue
		seen[entry.coordinate] = true
		result.append(entry)
	result.sort_custom(func(a: OWWorldCell, b: OWWorldCell) -> bool:
		var da := a.coordinate - center
		var db := b.coordinate - center
		var distance_a := da.x * da.x + da.y * da.y
		var distance_b := db.x * db.x + db.y * db.y
		if distance_a != distance_b:
			return distance_a < distance_b
		if a.coordinate.y != b.coordinate.y:
			return a.coordinate.y < b.coordinate.y
		return a.coordinate.x < b.coordinate.x
	)
	return result


func active_cell_count() -> int:
	return _active.size()


func pending_resource_count() -> int:
	return _pending_paths.size()


func is_cell_active(coordinate: Vector2i) -> bool:
	return _active.has(coordinate) and is_instance_valid(_active[coordinate])


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < maxf(check_interval, 0.1):
		return
	_elapsed = 0.0
	var viewer: Node3D = null
	if not viewer_path.is_empty():
		viewer = get_node_or_null(viewer_path) as Node3D
	if viewer == null:
		viewer = get_viewport().get_camera_3d()
	if viewer != null:
		update_streaming(viewer.global_position)


func _is_pending(coordinate: Vector2i) -> bool:
	for path in _pending_paths:
		if _pending_paths[path].has(coordinate):
			return true
	return false


func _spawn_cell(packed: PackedScene, coordinate: Vector2i, path: String) -> bool:
	if is_cell_active(coordinate):
		return false
	if packed == null:
		cell_load_failed.emit(coordinate, path)
		return false
	var instance := packed.instantiate()
	if not instance is Node3D:
		push_warning("World cell root must be Node3D: " + path)
		cell_load_failed.emit(coordinate, path)
		instance.free()
		return false
	var spatial := instance as Node3D
	add_child(spatial)
	spatial.position = Vector3(coordinate.x * cell_size, 0.0, coordinate.y * cell_size)
	_active[coordinate] = spatial
	cell_loaded.emit(coordinate, spatial)
	return true


func _is_authorized(coordinate: Vector2i, path: String) -> bool:
	for entry in cells:
		if entry != null and entry.coordinate == coordinate:
			return entry.scene_path == path
	return false


func _poll_requests(center: Vector2i) -> void:
	for path in _pending_paths.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		var coordinates: Array = _pending_paths[path]
		_pending_paths.erase(path)
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			for coord in coordinates:
				cell_load_failed.emit(coord, path)
			continue
		var packed := ResourceLoader.load_threaded_get(path) as PackedScene
		for coord in coordinates:
			var delta: Vector2i = coord - center
			if maxi(absi(delta.x), absi(delta.y)) <= maxi(0, load_radius) and _is_authorized(coord, path):
				_spawn_cell(packed, coord, path)


func update_streaming(viewer_world_position: Vector3) -> void:
	var center := world_to_cell(viewer_world_position)
	var keep_radius := maxi(load_radius, unload_radius)
	for coordinate in _active.keys():
		var delta: Vector2i = coordinate - center
		if maxi(absi(delta.x), absi(delta.y)) > keep_radius:
			var instance: Node = _active[coordinate]
			_active.erase(coordinate)
			if is_instance_valid(instance):
				instance.queue_free()
			cell_unloaded.emit(coordinate)
	_poll_requests(center)
	var started := 0
	for entry in planned_cells(center):
		if started >= maxi(1, max_cells_per_update):
			break
		if is_cell_active(entry.coordinate) or _is_pending(entry.coordinate):
			continue
		var path := entry.scene_path
		if threaded_loading:
			if _pending_paths.has(path):
				_pending_paths[path].append(entry.coordinate)
			else:
				if _pending_paths.size() >= maxi(1, max_pending_requests):
					break
				var status := ResourceLoader.load_threaded_request(path, "PackedScene")
				if status != OK:
					cell_load_failed.emit(entry.coordinate, path)
					continue
				_pending_paths[path] = [entry.coordinate]
		else:
			_spawn_cell(load(path) as PackedScene, entry.coordinate, path)
		started += 1


func _exit_tree() -> void:
	_pending_paths.clear()
	_active.clear()
