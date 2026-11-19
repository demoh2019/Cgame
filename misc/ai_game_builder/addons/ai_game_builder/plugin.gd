@tool
extends EditorPlugin

const AssistantDock = preload("res://addons/ai_game_builder/ai_dock.gd")
var editor_dock: EditorDock


func _enter_tree() -> void:
	editor_dock = EditorDock.new()
	editor_dock.title = "AI Game Builder"
	editor_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	editor_dock.add_child(AssistantDock.new())
	add_dock(editor_dock)


func _exit_tree() -> void:
	if editor_dock != null:
		remove_dock(editor_dock)
		editor_dock.queue_free()
		editor_dock = null
