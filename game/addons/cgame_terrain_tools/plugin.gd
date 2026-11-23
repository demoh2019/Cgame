@tool
extends EditorPlugin
## Terrain tools dock: brush/layer panel and material layer panel in tabs.
## Not enabled by default; turn it on in Project Settings > Plugins.

const TerrainPanel = preload("res://addons/cgame_terrain_tools/terrain_panel.gd")
const MaterialLayerPanel = preload("res://addons/cgame_terrain_tools/material_layer_panel.gd")

var terrain_panel: TerrainPanel = null
var material_panel: MaterialLayerPanel = null
var _dock: TabContainer = null
var _selection: EditorSelection = null


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
	_selection = get_editor_interface().get_selection()
	_selection.selection_changed.connect(_on_selection_changed)
	_on_selection_changed()


func _exit_tree() -> void:
	if _selection != null:
		_selection.selection_changed.disconnect(_on_selection_changed)
		_selection = null
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	terrain_panel = null
	material_panel = null


func _on_selection_changed() -> void:
	if terrain_panel == null or _selection == null:
		return
	for node in _selection.get_selected_nodes():
		if node is ChunkedTerrain3D:
			terrain_panel.attach_terrain(node)
			return
	terrain_panel.live_target = null



## Only intercept clicks while the explicit sculpt toggle is enabled.
## This leaves ordinary scene selection, handles and camera navigation intact.
func _handles(object: Object) -> bool:
	return object is ChunkedTerrain3D


func _sample_brush(camera: Camera3D, screen_position: Vector2) -> Vector2:
	var terrain: ChunkedTerrain3D = terrain_panel.live_target
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var direction: Vector3 = camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.0001:
		return Vector2.INF
	# Intersection with the current heightfield (not a fixed Y plane).
	# No collision node is required, so purely visual terrain is editable.
	var distance: float = (terrain.global_position.y - ray_origin.y) / direction.y
	for _i in 8:
		if not is_finite(distance) or distance <= 0.0:
			return Vector2.INF
		var point: Vector3 = ray_origin + direction * distance
		if not terrain.is_over_terrain(point):
			return Vector2.INF
		var height: float = terrain.get_height_at(point)
		distance = (height - ray_origin.y) / direction.y
	var hit: Vector3 = terrain.to_local(ray_origin + direction * distance)
	var dimensions: Vector2i = terrain.get_height_dimensions()
	var offset: Vector2 = terrain.size * 0.5 if terrain.centered else Vector2.ZERO
	var grid_x: float = (hit.x + offset.x) * float(dimensions.x - 1) / terrain.size.x
	var grid_z: float = (hit.z + offset.y) * float(dimensions.y - 1) / terrain.size.y
	return Vector2(grid_x, grid_z)


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if terrain_panel == null or not terrain_panel.viewport_sculpt_enabled or \
			terrain_panel.live_target == null or \
			not is_instance_valid(terrain_panel.live_target):
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if not (event is InputEventMouseButton):
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	var mouse: InputEventMouseButton = event
	if mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed or \
			mouse.alt_pressed or mouse.ctrl_pressed or mouse.shift_pressed:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	var cell: Vector2 = _sample_brush(camera, mouse.position)
	if not cell.is_finite():
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	terrain_panel.stroke(PackedVector2Array([cell]))
	return EditorPlugin.AFTER_GUI_INPUT_STOP
