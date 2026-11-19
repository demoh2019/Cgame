@tool
extends EditorPlugin

const ASSISTANT_DOCK = preload("res://addons/ai_game_builder/assistant_dock.gd")

var _dock: EditorDock


func _enter_tree() -> void:
	_dock = EditorDock.new()
	_dock.title = "AI Game Builder"
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_BL
	_dock.name = "AI Game Builder"
	var panel := ASSISTANT_DOCK.new()
	panel.name = "Builder"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dock.add_child(panel)
	add_dock(_dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_dock(_dock)
		_dock.queue_free()
		_dock = null
