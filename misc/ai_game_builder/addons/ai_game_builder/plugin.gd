@tool
extends EditorPlugin

const BuilderDock = preload("res://addons/ai_game_builder/builder_dock.gd")

var _dock: EditorDock


func _enter_tree() -> void:
	var panel := BuilderDock.new()
	panel.name = "AI Game Builder"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_dock = EditorDock.new()
	_dock.title = "AI Builder"
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	_dock.available_layouts = EditorDock.DOCK_LAYOUT_VERTICAL | EditorDock.DOCK_LAYOUT_FLOATING
	_dock.add_child(panel)
	add_dock(_dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_dock(_dock)
		_dock.queue_free()
		_dock = null
