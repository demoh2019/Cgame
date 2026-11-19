@tool
extends EditorPlugin

const PCG_DOCK := preload("res://addons/pcg_graph/pcg_dock.gd")

var _panel: Control


func _enter_tree() -> void:
	_panel = PCG_DOCK.new()
	_panel.name = "PCG Graph"
	add_control_to_bottom_panel(_panel, "PCG Graph")


func _exit_tree() -> void:
	if is_instance_valid(_panel):
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
	_panel = null
