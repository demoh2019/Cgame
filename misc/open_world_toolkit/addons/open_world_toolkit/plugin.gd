@tool
extends EditorPlugin
## Editor integration for the Open World Toolkit demo project.

const DOCK := preload("res://addons/open_world_toolkit/terrain_brush_dock.gd")
const PCG_DOCK := preload("res://addons/open_world_toolkit/pcg_graph_dock.gd")

var dock: OWTerrainBrushDock
var pcg_dock: OWPCGGraphDock
var selected_terrain: OWTerrain3D
var _stroke_map: OWHeightmap
var _before_heights: PackedFloat32Array
var _before_blend: PackedFloat32Array
var _stroke_active: bool = false


func _enter_tree() -> void:
	dock = DOCK.new()
	pcg_dock = PCG_DOCK.new()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, dock)
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_BL, pcg_dock)
	pcg_dock.bake_requested.connect(_bake_pcg)
	dock.generate_requested.connect(_generate)
	dock.erode_requested.connect(_erode)
	dock.foliage_requested.connect(_scatter)
	EditorInterface.get_selection().selection_changed.connect(_update_selection)
	_update_selection()


func _exit_tree() -> void:
	_finish_stroke()
	if EditorInterface.get_selection().selection_changed.is_connected(_update_selection):
		EditorInterface.get_selection().selection_changed.disconnect(_update_selection)
	remove_control_from_docks(dock)
	remove_control_from_docks(pcg_dock)
	dock.queue_free()
	pcg_dock.queue_free()


func _handles(object: Object) -> bool:
	return object is OWTerrain3D


func _update_selection() -> void:
	_finish_stroke()
	selected_terrain = null
	for candidate in EditorInterface.get_selection().get_selected_nodes():
		if candidate is OWTerrain3D:
			selected_terrain = candidate
			break
	if dock != null:
		dock.set_terrain(selected_terrain)
	if pcg_dock != null:
		pcg_dock.set_terrain(selected_terrain)


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if selected_terrain == null or dock == null or not dock.paint_enabled.button_pressed:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_start_stroke()
			_paint_from_mouse(camera, event.position)
		else:
			_finish_stroke()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion and _stroke_active and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_paint_from_mouse(camera, event.position)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _paint_from_mouse(camera: Camera3D, screen_position: Vector2) -> void:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var hit: Variant = selected_terrain.intersect_world_ray(origin, direction)
	if hit != null:
		dock.apply_brush(selected_terrain.to_local(hit))


func _start_stroke() -> void:
	if selected_terrain == null or selected_terrain.heightmap == null:
		return
	_stroke_active = true
	_stroke_map = selected_terrain.heightmap
	_before_heights = _stroke_map.heights.duplicate()
	_before_blend = _stroke_map.blend.duplicate()


func _finish_stroke() -> void:
	if not _stroke_active:
		return
	_stroke_active = false
	if is_instance_valid(_stroke_map):
		_commit_snapshot(_stroke_map, _before_heights, _before_blend, "Paint terrain")
	_stroke_map = null


func _commit_snapshot(data: OWHeightmap, old_heights: PackedFloat32Array, old_blend: PackedFloat32Array, label: String) -> void:
	if data.heights == old_heights and data.blend == old_blend:
		return
	var new_heights := data.heights.duplicate()
	var new_blend := data.blend.duplicate()
	var history := get_undo_redo()
	history.create_action(label)
	history.add_do_method(data, "set_snapshots", new_heights, new_blend)
	history.add_undo_method(data, "set_snapshots", old_heights, old_blend)
	history.commit_action(false)


func _generate() -> void:
	if selected_terrain == null or selected_terrain.heightmap == null:
		return
	var data := selected_terrain.heightmap
	var old_heights := data.heights.duplicate()
	var old_blend := data.blend.duplicate()
	data.generate_noise(int(dock.noise_seed.value), 0.04, dock.noise_amplitude.value)
	_commit_snapshot(data, old_heights, old_blend, "Generate terrain")


func _erode() -> void:
	if selected_terrain == null or selected_terrain.heightmap == null:
		return
	var data := selected_terrain.heightmap
	var old_heights := data.heights.duplicate()
	var old_blend := data.blend.duplicate()
	data.erode(int(dock.erosion_iterations.value))
	_commit_snapshot(data, old_heights, old_blend, "Erode terrain")


func _scatter() -> void:
	if selected_terrain == null:
		return
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return
	_scatter_in_subtree(scene_root)


func _scatter_in_subtree(parent: Node) -> void:
	for node in parent.get_children():
		if node is OWFoliageScatter3D and node.terrain == selected_terrain:
			var old_multimesh: MultiMesh = node.multimesh
			if node.scatter() == 0 and old_multimesh == null:
				continue
			var new_multimesh: MultiMesh = node.multimesh
			var history := get_undo_redo()
			history.create_action("Scatter foliage")
			history.add_do_property(node, "multimesh", new_multimesh)
			history.add_undo_property(node, "multimesh", old_multimesh)
			history.commit_action(false)

		_scatter_in_subtree(node)


func _bake_pcg() -> void:
	if selected_terrain == null or selected_terrain.heightmap == null or selected_terrain.pcg_graph == null:
		return
	var data := selected_terrain.heightmap
	var old_heights := data.heights.duplicate()
	var old_blend := data.blend.duplicate()
	if not selected_terrain.pcg_graph.bake_to_heightmap(data):
		push_warning("PCG graph could not be baked: " + selected_terrain.pcg_graph.validation_error())
		return
	_commit_snapshot(data, old_heights, old_blend, "Bake terrain PCG graph")