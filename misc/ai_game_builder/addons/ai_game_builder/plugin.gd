@tool
extends EditorPlugin

const BuilderDock = preload("res://addons/ai_game_builder/dock.gd")

var _dock: Control


func _enter_tree() -> void:
	_dock = BuilderDock.new()
	_dock.name = "AI Game Builder"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if is_instance_valid(_dock):
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
