extends Node
class_name WorldStateStore3D
## Persist state of streamed Node3D cells without keeping unloaded nodes alive.
## Cell protocol: save_stream_state() -> Dictionary and load_stream_state(Dictionary).
## Attach this store to a WorldStreamer3D before streaming begins.

signal state_saved(path: String, cell_count: int)
signal save_failed(error: int)
signal state_restored(coord: Vector2i)

const SAVE_VERSION: int = 1
const MAX_SAVED_CELLS: int = 16384
const MAX_STATE_FIELDS: int = 64

@export var world_id: String = "visual_quality_lab_forest_v1"
@export var save_path: String = "user://visual_quality_world_state_v1.cfg"
@export var autosave_on_change: bool = true
@export var save_on_exit: bool = true

var streamer: WorldStreamer3D
var _states: Dictionary = {} # Cell key "x:z" -> sanitized Dictionary
var _connected: bool = false


func _ready() -> void:
	load_from_disk()
	if streamer != null:
		bind_to_streamer(streamer)


func _exit_tree() -> void:
	if save_on_exit:
		save_now()


func bind_to_streamer(target: WorldStreamer3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	if _connected and streamer != null and is_instance_valid(streamer):
		if streamer.cell_loaded.is_connected(_on_cell_loaded):
			streamer.cell_loaded.disconnect(_on_cell_loaded)
		if streamer.cell_about_to_unload.is_connected(_on_cell_about_to_unload):
			streamer.cell_about_to_unload.disconnect(_on_cell_about_to_unload)
	streamer = target
	streamer.cell_loaded.connect(_on_cell_loaded)
	streamer.cell_about_to_unload.connect(_on_cell_about_to_unload)
	_connected = true
	# Handles stores attached after some cells were already instantiated.
	for cell in streamer.get_active_cells():
		if cell.has_method("load_stream_state") and cell.has_method("get_stream_cell_coord"):
			_on_cell_loaded(cell.call("get_stream_cell_coord"), cell)


func _on_cell_loaded(coord: Vector2i, cell: Node3D) -> void:
	if cell == null or not is_instance_valid(cell):
		return
	var state: Dictionary = get_saved_state(coord)
	if not state.is_empty() and cell.has_method("load_stream_state"):
		cell.call("load_stream_state", state)
		state_restored.emit(coord)
	if cell.has_signal("stream_state_changed"):
		var callback: Callable = _on_cell_state_changed.bind(coord)
		if not cell.is_connected("stream_state_changed", callback):
			cell.connect("stream_state_changed", callback)


func _on_cell_about_to_unload(coord: Vector2i, cell: Node3D) -> void:
	var before: Dictionary = get_saved_state(coord)
	capture_cell(coord, cell)
	# Unloading is a save boundary too: supports cells that mutate state
	# without emitting stream_state_changed.
	if autosave_on_change and before != get_saved_state(coord):
		save_now()


func _on_cell_state_changed(coord: Vector2i) -> void:
	if streamer == null or not is_instance_valid(streamer):
		return
	capture_cell(coord, streamer.get_active_cell(coord))
	if autosave_on_change:
		save_now()


func capture_cell(coord: Vector2i, cell: Node3D) -> void:
	if cell == null or not is_instance_valid(cell) or not cell.has_method("save_stream_state"):
		return
	var sanitized: Dictionary = sanitize_state(cell.call("save_stream_state"))
	var key: String = cell_key(coord)
	if sanitized.is_empty():
		_states.erase(key)
	elif _states.has(key) or _states.size() < MAX_SAVED_CELLS:
		_states[key] = sanitized


func capture_active_cells() -> void:
	if streamer == null or not is_instance_valid(streamer):
		return
	for cell in streamer.get_active_cells():
		if cell.has_method("get_stream_cell_coord"):
			capture_cell(cell.call("get_stream_cell_coord"), cell)


func save_now() -> Error:
	capture_active_cells()
	if not save_path.begins_with("user://"):
		save_failed.emit(ERR_INVALID_PARAMETER)
		return ERR_INVALID_PARAMETER
	var config: ConfigFile = ConfigFile.new()
	config.set_value("world", "version", SAVE_VERSION)
	config.set_value("world", "world_id", world_id)
	config.set_value("world", "cells", _states)
	# Write a temporary file and rename it. Never invalidate a valid older save
	# when serialization fails part way through writing.
	var temp_path: String = save_path + ".tmp"
	var result: Error = config.save(temp_path)
	if result == OK:
		result = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(temp_path),
			ProjectSettings.globalize_path(save_path)
		)
	if result != OK:
		save_failed.emit(result)
		return result
	state_saved.emit(save_path, _states.size())
	return OK


func load_from_disk() -> bool:
	_states.clear()
	if not save_path.begins_with("user://"):
		return false
	var config: ConfigFile = ConfigFile.new()
	if config.load(save_path) != OK:
		return false
	if config.get_value("world", "version", 0) != SAVE_VERSION:
		return false
	if config.get_value("world", "world_id", "") != world_id:
		return false
	var raw: Variant = config.get_value("world", "cells", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return false
	for key in raw.keys():
		if _states.size() >= MAX_SAVED_CELLS:
			break
		if typeof(key) != TYPE_STRING or not valid_cell_key(key):
			continue
		var state: Dictionary = sanitize_state(raw[key])
		if not state.is_empty():
			_states[key] = state
	return true


func get_saved_state(coord: Vector2i) -> Dictionary:
	return _states.get(cell_key(coord), {}).duplicate(true)


func saved_cell_count() -> int:
	return _states.size()


func clear_all_states() -> void:
	_states.clear()
	if streamer != null and is_instance_valid(streamer):
		for cell in streamer.get_active_cells():
			if cell.has_method("load_stream_state"):
				cell.call("load_stream_state", {})
	save_now()


static func cell_key(coord: Vector2i) -> String:
	return "%d:%d" % [coord.x, coord.y]


static func valid_cell_key(value: String) -> bool:
	var parts: PackedStringArray = value.split(":")
	return parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int()


## Deliberately accept only small, native serializable primitive values.
## A cell cannot write Node/Object/Resource references into the saved file.
static func sanitize_state(raw: Variant) -> Dictionary:
	var clean: Dictionary = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return clean
	for key in raw.keys():
		if clean.size() >= MAX_STATE_FIELDS:
			break
		if typeof(key) != TYPE_STRING or key.is_empty() or key.length() > 64:
			continue
		var value: Variant = raw[key]
		match typeof(value):
			TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_COLOR:
				clean[key] = value
			TYPE_STRING:
				if value.length() <= 2048:
					clean[key] = value
	return clean
