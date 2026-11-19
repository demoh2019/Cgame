@tool
extends EditorPlugin
## Minimal editor authoring UI for OpenWorldTerrain.

const TERRAIN: Script = preload("res://addons/open_world/terrain_world.gd")

enum ToolMode { SELECT, RAISE, LOWER, SMOOTH, PAINT }

var _dock: VBoxContainer
var _mode: OptionButton
var _layer: OptionButton
var _radius: SpinBox
var _strength: SpinBox
var _foliage_count: SpinBox
var _foliage_seed: SpinBox
var _selection_label: Label
var _active: Node3D
var _stroke_node: Node3D
var _stroke_heights: PackedFloat32Array
var _stroke_paint: PackedColorArray


func _enter_tree() -> void:
	add_custom_type("OpenWorldTerrain", "Node3D", TERRAIN, null)
	_dock = VBoxContainer.new()
	_dock.name = "Open World"
	_dock.custom_minimum_size = Vector2(220, 0)

	var create_button := Button.new()
	create_button.text = "Create Terrain"
	create_button.pressed.connect(_create_terrain)
	_dock.add_child(create_button)

	_selection_label = Label.new()
	_selection_label.text = "Select an OpenWorldTerrain node"
	_dock.add_child(_selection_label)

	_mode = OptionButton.new()
	for label in ["Select / Navigate", "Raise height", "Lower height", "Smooth height", "Paint texture"]:
		_mode.add_item(label)
	_dock.add_child(_labeled_control("Tool", _mode))

	_layer = OptionButton.new()
	for layer in range(4):
		_layer.add_item("Material layer %d" % layer)
	_dock.add_child(_labeled_control("Paint layer", _layer))

	_radius = _make_spin(0.5, 64.0, 3.0, 0.5)
	_dock.add_child(_labeled_control("Brush radius", _radius))
	_strength = _make_spin(0.05, 10.0, 0.5, 0.05)
	_dock.add_child(_labeled_control("Brush strength", _strength))

	var rebuild_button := Button.new()
	rebuild_button.text = "Rebuild mesh / material"
	rebuild_button.pressed.connect(_rebuild)
	_dock.add_child(rebuild_button)

	var erosion_button := Button.new()
	erosion_button.text = "Apply thermal erosion"
	erosion_button.pressed.connect(_erode)
	_dock.add_child(erosion_button)

	_foliage_count = _make_spin(0, 10000, 250, 1)
	_dock.add_child(_labeled_control("Foliage instances", _foliage_count))
	_foliage_seed = _make_spin(0, 2147483647, 42, 1)
	_dock.add_child(_labeled_control("Random seed", _foliage_seed))

	var scatter_button := Button.new()
	scatter_button.text = "Scatter foliage (MultiMesh)"
	scatter_button.pressed.connect(_scatter)
	_dock.add_child(scatter_button)

	var help := Label.new()
	help.text = "Select terrain, choose a tool, then left-drag in the 3D viewport. Assign a Mesh to 'Foliage Mesh' in the Inspector."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dock.add_child(help)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	_finish_stroke()
	remove_control_from_docks(_dock)
	_dock.queue_free()
	remove_custom_type("OpenWorldTerrain")


func _labeled_control(title: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = title
	box.add_child(label)
	box.add_child(control)
	return box


func _make_spin(minimum: float, maximum: float, default_value: float, step_value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step_value
	spin.value = default_value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


func _handles(object: Object) -> bool:
	return object is Node3D and object.get_script() == TERRAIN


func _edit(object: Object) -> void:
	_finish_stroke()
	if _handles(object):
		_active = object as Node3D
	else:
		_active = null
	if is_instance_valid(_selection_label):
		_selection_label.text = "Editing: " + _active.name if is_instance_valid(_active) else "Select an OpenWorldTerrain node"


func _create_terrain() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		push_warning("Open a scene before creating a terrain.")
		return
	var terrain := TERRAIN.new() as Node3D
	terrain.name = "OpenWorldTerrain"
	# The undo manager owns the new node until it is added.
	var history := get_undo_redo()
	history.create_action("Create Open World Terrain")
	history.add_do_method(root, "add_child", terrain)
	history.add_do_method(terrain, "set_owner", root)
	history.add_undo_method(root, "remove_child", terrain)
	history.add_do_reference(terrain)
	history.commit_action()
	terrain.call("rebuild")
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(terrain)
	EditorInterface.mark_scene_as_unsaved()


func _rebuild() -> void:
	if is_instance_valid(_active):
		_active.call("rebuild")
		EditorInterface.mark_scene_as_unsaved()


func _erode() -> void:
	if not is_instance_valid(_active):
		return
	var old_heights: PackedFloat32Array = _active.call("get_height_copy")
	var old_paint: PackedColorArray = _active.call("get_paint_copy")
	_active.call("thermal_erode", 1, 0.25, 0.2)
	_save_terrain_action("Thermal Erosion", _active, old_heights, old_paint)


func _scatter() -> void:
	if not is_instance_valid(_active):
		return
	var before_points: PackedVector3Array = _active.call("get_foliage_points_copy")
	var before_scales: PackedFloat32Array = _active.call("get_foliage_scales_copy")
	_active.call("scatter_foliage", int(_foliage_count.value), int(_foliage_seed.value), 0.7)
	var after_points: PackedVector3Array = _active.call("get_foliage_points_copy")
	var after_scales: PackedFloat32Array = _active.call("get_foliage_scales_copy")
	var history := get_undo_redo()
	history.create_action("Scatter Foliage")
	history.add_do_method(_active, "restore_foliage", after_points, after_scales)
	history.add_undo_method(_active, "restore_foliage", before_points, before_scales)
	history.commit_action()


func _save_terrain_action(title: String, terrain: Node3D, old_heights: PackedFloat32Array, old_paint: PackedColorArray) -> void:
	if not is_instance_valid(terrain):
		return
	var new_heights: PackedFloat32Array = terrain.call("get_height_copy")
	var new_paint: PackedColorArray = terrain.call("get_paint_copy")
	if old_heights == new_heights and old_paint == new_paint:
		return
	var history := get_undo_redo()
	history.create_action(title)
	history.add_do_method(terrain, "restore_data", new_heights, new_paint)
	history.add_undo_method(terrain, "restore_data", old_heights, old_paint)
	history.commit_action()


func _get_terrain_hit(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	if not is_instance_valid(_active) or not _active.is_inside_tree():
		return {}
	var origin: Vector3 = camera.project_ray_origin(screen_pos)
	var direction: Vector3 = camera.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 10000.0)
	var result: Dictionary = camera.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty() or result.get("collider") != _active.call("get_collision_body"):
		return {}
	return result


func _paint_at(camera: Camera3D, screen_pos: Vector2) -> bool:
	var hit: Dictionary = _get_terrain_hit(camera, screen_pos)
	if hit.is_empty():
		return false
	var brush_mode: int = _mode.get_selected_id() - 1
	_active.call("apply_brush", hit["position"], _radius.value, _strength.value, brush_mode, _layer.get_selected_id())
	return true


func _finish_stroke() -> void:
	if not is_instance_valid(_stroke_node):
		_stroke_node = null
		return
	_save_terrain_action("Terrain Brush Stroke", _stroke_node, _stroke_heights, _stroke_paint)
	_stroke_node = null


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not is_instance_valid(_active) or _mode.get_selected_id() == ToolMode.SELECT:
		return AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _get_terrain_hit(camera, event.position).is_empty():
				return AFTER_GUI_INPUT_PASS
			_finish_stroke()
			_stroke_node = _active
			_stroke_heights = _active.call("get_height_copy")
			_stroke_paint = _active.call("get_paint_copy")
			_paint_at(camera, event.position)
			return AFTER_GUI_INPUT_STOP
		if is_instance_valid(_stroke_node):
			_finish_stroke()
			return AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion and is_instance_valid(_stroke_node):
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_paint_at(camera, event.position)
			return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS
