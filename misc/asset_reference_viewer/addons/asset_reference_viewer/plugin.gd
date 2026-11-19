@tool
extends EditorPlugin

const Dock = preload("res://addons/asset_reference_viewer/dock.gd")

var _dock: Control


func _enter_tree() -> void:
	_dock = Dock.new()
	_dock.name = "Asset References"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)


func _exit_tree() -> void:
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem.filesystem_changed.is_connected(_on_filesystem_changed):
		filesystem.filesystem_changed.disconnect(_on_filesystem_changed)
	if is_instance_valid(_dock):
		remove_control_from_docks(_dock)
		_dock.queue_free()


func _on_filesystem_changed() -> void:
	if is_instance_valid(_dock):
		_dock.invalidate_index()
