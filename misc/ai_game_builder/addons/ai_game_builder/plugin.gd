@tool
extends EditorPlugin

const AI_DOCK = preload("res://addons/ai_game_builder/dock.gd")
var _dock: EditorDock


func _enter_tree() -> void:
	_dock = EditorDock.new()
	_dock.title = "AI Game Builder"
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	_dock.add_child(AI_DOCK.new())
	add_dock(_dock)


func _exit_tree() -> void:
	if is_instance_valid(_dock):
		remove_dock(_dock)
		_dock.queue_free()
