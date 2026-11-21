@tool
extends EditorPlugin
## Adds the "Cgame Graphs" bottom panel hosting the generic graph editor.
## Original code; uses Godot's EditorPlugin / GraphEdit APIs (Godot Engine, MIT licence).

const GraphEditorPanel = preload("res://addons/cgame_graph_editors/graph_editor.gd")

var _panel: Control


func _enter_tree() -> void:
	_panel = GraphEditorPanel.new()
	_panel.name = "Cgame Graphs"
	_panel.custom_minimum_size = Vector2(0, 320)
	add_control_to_bottom_panel(_panel, "Cgame Graphs")


func _exit_tree() -> void:
	if _panel != null:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null
