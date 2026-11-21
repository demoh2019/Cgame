@tool
extends EditorPlugin
## Procgen tools dock (settlements, roads, rivers, caves). Not enabled by default;
## turn it on in Project Settings > Plugins.

const ProcgenPanel = preload("res://addons/cgame_procgen_tools/procgen_panel.gd")

var panel: ProcgenPanel = null


func _enter_tree() -> void:
	panel = ProcgenPanel.new()
	panel.name = "Cgame Procgen"
	add_control_to_dock(DOCK_SLOT_LEFT_BR, panel)


func _exit_tree() -> void:
	if panel != null:
		remove_control_from_docks(panel)
		panel.queue_free()
		panel = null
