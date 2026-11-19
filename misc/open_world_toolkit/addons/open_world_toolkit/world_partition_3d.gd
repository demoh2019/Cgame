extends Node3D
class_name OWWorldPartition3D
## Runtime streaming of authored cells around a viewer with unload hysteresis.
## Only scenes explicitly referenced in `cells` are ever loaded.

@export_range(1.0, 100000.0, 1.0) var cell_size: float = 256.0
@export_range(0, 16, 1) var load_radius: int = 1
@export_range(0, 24, 1) var unload_radius: int = 2
@export_range(0.1, 5.0, 0.1) var check_interval: float = 0.5
@export var viewer_path: NodePath
@export var cells: Array[OWWorldCell] = []

var _active: Dictionary = {}
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


func active_cell_count() -> int:
	return _active.size()


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


func update_streaming(viewer_world_position: Vector3) -> void:
	var center := world_to_cell(viewer_world_position)
	var keep_radius := maxi(load_radius, unload_radius)
	for key in _active.keys():
		var coordinate: Vector2i = key
		if maxi(absi(coordinate.x - center.x), absi(coordinate.y - center.y)) > keep_radius:
			var instance: Node = _active[key]
			_active.erase(key)
			instance.queue_free()
	var wanted := wanted_cells(center, load_radius)
	for entry in cells:
		if entry == null or entry.scene_path.is_empty() or _active.has(entry.coordinate):
			continue
		if not wanted.has(entry.coordinate):
			continue
		var packed := load(entry.scene_path) as PackedScene
		if packed == null:
			push_warning("Could not load world cell: " + entry.scene_path)
			continue
		var instance := packed.instantiate()
		if not instance is Node3D:
			push_warning("World cell root must be Node3D: " + entry.scene_path)
			instance.free()
			continue
		add_child(instance)
		instance.position = Vector3(entry.coordinate.x * cell_size, 0.0, entry.coordinate.y * cell_size)
		_active[entry.coordinate] = instance


func _exit_tree() -> void:
	_active.clear()