@tool
extends EditorPlugin

const BuilderDock = preload("res://addons/ai_game_builder/dock.gd")
var _dock: EditorDock


func _enter_tree() -> void:
	_dock = EditorDock.new()
	_dock.title = "AI Game Builder"
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	_dock.add_child(BuilderDock.new())
	add_dock(_dock)


func _exit_tree() -> void:
	remove_dock(_dock)
	_dock.queue_free()
	_dock = null
