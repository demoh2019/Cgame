@tool
extends EditorPlugin

const AIDock = preload("res://addons/ai_game_builder/dock.gd")

var _dock: Control


func _enter_tree() -> void:
	_dock = AIDock.new()
	add_control_to_bottom_panel(_dock, "AI Game Builder")


func _exit_tree() -> void:
	if is_instance_valid(_dock):
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
