@tool
extends EditorPlugin
## Terrain tools dock: brush/layer panel and material layer panel in tabs.
## Not enabled by default; turn it on in Project Settings > Plugins.

const TerrainPanel = preload("res://addons/cgame_terrain_tools/terrain_panel.gd")
const MaterialLayerPanel = preload("res://addons/cgame_terrain_tools/material_layer_panel.gd")

var terrain_panel: TerrainPanel = null
var material_panel: MaterialLayerPanel = null
var _dock: TabContainer = null


func _enter_tree() -> void:
	terrain_panel = TerrainPanel.new()
	terrain_panel.name = "Terrain"
	material_panel = MaterialLayerPanel.new()
	material_panel.name = "Material"
	_dock = TabContainer.new()
	_dock.name = "Cgame Terrain"
	_dock.add_child(terrain_panel)
	_dock.add_child(material_panel)
	add_control_to_dock(DOCK_SLOT_LEFT_BR, _dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	terrain_panel = null
	material_panel = null
