@tool
extends EditorPlugin
## Small editor toolbar for painting and sculpting WorldTerrain3D nodes.

var _selected: WorldTerrain3D
var _foliage: WorldFoliage3D
var _toolbar: HBoxContainer
var _mode: OptionButton
var _radius: SpinBox
var _strength: SpinBox
var _paint: ColorPickerButton
var _texture_layer: OptionButton
var _stroke_active: bool = false
var _stroke_changed: bool = false
var _start_heights: PackedFloat32Array
var _start_colors: PackedColorArray
var _start_weights: PackedColorArray
var _flatten_height: float = 0.0


func _enter_tree() -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.name = "Open World Tools"
	_mode = OptionButton.new()
	for label in ["Raise / Shift Lower", "Smooth", "Flatten", "Paint Vertex Color", "Paint Texture Layer"]:
		_mode.add_item(label)
	_toolbar.add_child(_mode)
	_radius = SpinBox.new()
	_radius.min_value = 0.5
	_radius.max_value = 128.0
	_radius.step = 0.5
	_radius.value = 6.0
	_radius.tooltip_text = "Brush radius in terrain local units"
	_toolbar.add_child(_radius)
	_strength = SpinBox.new()
	_strength.min_value = 0.01
	_strength.max_value = 20.0
	_strength.step = 0.05
	_strength.value = 0.75
	_strength.tooltip_text = "Strength per brush sample"
	_toolbar.add_child(_strength)
	_paint = ColorPickerButton.new()
	_paint.color = Color(0.58, 0.43, 0.25)
	_paint.custom_minimum_size = Vector2(26, 0)
	_toolbar.add_child(_paint)
	_texture_layer = OptionButton.new()
	for i in range(4):
		_texture_layer.add_item("Texture %d" % (i + 1))
	_toolbar.add_child(_texture_layer)
	var rebuild: Button = Button.new()
	rebuild.text = "Rebuild Terrain"
	rebuild.pressed.connect(_rebuild_selected)
	_toolbar.add_child(rebuild)
	var scatter: Button = Button.new()
	scatter.text = "Scatter Foliage"
	scatter.pressed.connect(_scatter_selected)
	_toolbar.add_child(scatter)
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
	_toolbar.hide()


func _exit_tree() -> void:
	_finish_stroke()
	remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
	_toolbar.free()
	_toolbar = null


func _handles(object: Object) -> bool:
	return object is WorldTerrain3D or object is WorldFoliage3D


func _edit(object: Object) -> void:
	_finish_stroke()
	_selected = object as WorldTerrain3D
	_foliage = object as WorldFoliage3D
	if _toolbar:
		_toolbar.visible = _selected != null or _foliage != null


func _make_visible(visible: bool) -> void:
	if not visible:
		_finish_stroke()
	if _toolbar:
		_toolbar.visible = visible and (_selected != null or _foliage != null)


func _rebuild_selected() -> void:
	if is_instance_valid(_selected):
		_selected.rebuild()


func _scatter_selected() -> void:
	if not is_instance_valid(_foliage):
		return
	var previous: MultiMesh = _foliage.multimesh
	_foliage.scatter()
	var replacement: MultiMesh = _foliage.multimesh
	var history: EditorUndoRedoManager = get_undo_redo()
	history.create_action("Scatter World Foliage")
	history.add_do_property(_foliage, "multimesh", replacement)
	history.add_undo_property(_foliage, "multimesh", previous)
	history.commit_action(false)


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not is_instance_valid(_selected) or not _selected.is_inside_tree():
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index != MOUSE_BUTTON_LEFT:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		if not button.pressed:
			if _stroke_active:
				_finish_stroke()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		if button.alt_pressed or button.ctrl_pressed:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		var hit: Variant = _terrain_ray_hit(camera, button.position)
		if hit == null:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		_start_heights = _selected.height_data.duplicate()
		_start_colors = _selected.color_data.duplicate()
		_start_weights = _selected.weight_data.duplicate()
		_flatten_height = (hit as Vector3).y
		_stroke_active = true
		_stroke_changed = false
		_stamp(hit as Vector3, button.shift_pressed)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion and _stroke_active:
		var motion: InputEventMouseMotion = event
		var hit: Variant = _terrain_ray_hit(camera, motion.position)
		if hit != null:
			_stamp(hit as Vector3, motion.shift_pressed)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _stamp(hit: Vector3, shift_down: bool) -> void:
	var power: float = float(_strength.value)
	if _mode.selected == 0 and shift_down:
		power = -power
	var changed: int = _selected.apply_brush(hit, float(_radius.value), power, _mode.selected, _flatten_height, _paint.color, _texture_layer.selected)
	_stroke_changed = _stroke_changed or changed > 0


func _finish_stroke() -> void:
	if not _stroke_active:
		return
	_stroke_active = false
	if not _stroke_changed or not is_instance_valid(_selected):
		return
	var after_heights: PackedFloat32Array = _selected.height_data.duplicate()
	var after_colors: PackedColorArray = _selected.color_data.duplicate()
	var after_weights: PackedColorArray = _selected.weight_data.duplicate()
	var history: EditorUndoRedoManager = get_undo_redo()
	history.create_action("Edit World Terrain")
	history.add_do_method(_selected, "restore_samples", after_heights, after_colors, after_weights)
	history.add_undo_method(_selected, "restore_samples", _start_heights, _start_colors, _start_weights)
	history.commit_action(false)
	_stroke_changed = false


func _terrain_ray_hit(camera: Camera3D, screen_pos: Vector2) -> Variant:
	# Iteratively project onto the local heightfield instead of assuming flat Y=0.
	# This is an approximation on overhang-free heightfields, not a physics raycast.
	var origin: Vector3 = _selected.to_local(camera.project_ray_origin(screen_pos))
	var direction: Vector3 = _selected.global_transform.affine_inverse().basis * camera.project_ray_normal(screen_pos)
	if absf(direction.y) < 0.00001:
		return null
	var elevation: float = 0.0
	var hit: Vector3 = Vector3.ZERO
	for iteration in range(8):
		var distance: float = (elevation - origin.y) / direction.y
		if distance < 0.0 or distance > camera.far:
			return null
		hit = origin + direction * distance
		if not _selected.contains_xz(hit.x, hit.z):
			return null
		elevation = _selected.get_height_at(hit.x, hit.z)
	return hit