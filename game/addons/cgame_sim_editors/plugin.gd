@tool
extends EditorPlugin
## Docks the sim editor panels (vehicle, cloth, VFX budget, VFX debugger) in a tab container.
## Original code. Not enabled by default in project.godot.

var _dock: TabContainer


func _enter_tree() -> void:
	_dock = TabContainer.new()
	_dock.name = "Sim Editors"
	var scripts: Dictionary = {
		"Vehicle": "res://addons/cgame_sim_editors/vehicle_panel.gd",
		"Cloth": "res://addons/cgame_sim_editors/cloth_panel.gd",
		"VFX Budget": "res://addons/cgame_sim_editors/vfx_budget_panel.gd",
		"VFX Debugger": "res://addons/cgame_sim_editors/vfx_debugger_panel.gd",
	}
	for title in scripts:
		var script: GDScript = load(str(scripts[title]))
		var panel: Control = script.new()
		panel.name = str(title)
		_dock.add_child(panel)
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
