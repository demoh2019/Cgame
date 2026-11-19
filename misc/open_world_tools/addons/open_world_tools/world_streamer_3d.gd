extends Node3D
class_name WorldStreamer3D
## Synchronous prototype world partition: loads scenes near a focus Node3D.
## Replace instantiate() with threaded loading for production projects.

@export var focus: Node3D
@export_range(1.0, 8192.0, 1.0) var cell_size: float = 64.0
@export_range(0, 32, 1) var active_radius: int = 2
@export var cells: Array[WorldStreamCell] = []

var _loaded: Dictionary = {}


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		update_streaming()


func update_streaming() -> void:
	if focus == null:
		clear_loaded()
		return
	var local_focus: Vector3 = to_local(focus.global_position)
	var center: Vector2i = Vector2i(floori(local_focus.x / cell_size), floori(local_focus.z / cell_size))
	var wanted: Dictionary = {}
	for cell in cells:
		if cell == null or cell.scene == null:
			continue
		var key: Vector2i = cell.grid_coord
		if absi(key.x - center.x) > active_radius or absi(key.y - center.y) > active_radius:
			continue
		wanted[key] = true
		if _loaded.has(key):
			continue
		var instance: Node = cell.scene.instantiate()
		add_child(instance)
		if instance is Node3D:
			(instance as Node3D).position = Vector3(float(key.x) * cell_size, 0.0, float(key.y) * cell_size)
		_loaded[key] = instance
	for key in _loaded.keys():
		if not wanted.has(key):
			var old: Node = _loaded[key]
			_loaded.erase(key)
			old.queue_free()


func get_loaded_cell_count() -> int:
	return _loaded.size()


func clear_loaded() -> void:
	for node in _loaded.values():
		(node as Node).queue_free()
	_loaded.clear()


func _exit_tree() -> void:
	clear_loaded()