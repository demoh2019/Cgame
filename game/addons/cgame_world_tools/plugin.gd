@tool
extends EditorPlugin
## World tools dock: spline authoring (road / river / bridge) and foliage painting.
## Left-click in the 3D viewport adds a spline point (Spline tab) or paints/erases
## foliage (Foliage tab) on the ground plane (or on `height_at` when a terrain
## provider is assigned). Not enabled by default; turn it on in Project Settings.
##
## Note: the shared libraries (terrain_splines.gd, terrain_edit_layers.gd, pcg_graph.gd)
## must be @tool scripts for the tools to run inside the editor; a warning is pushed otherwise.

const SplineTool = preload("res://addons/cgame_world_tools/spline_tool.gd")
const FoliagePainter = preload("res://addons/cgame_world_tools/foliage_painter.gd")
const TerrainSplines = preload("res://scripts/shared/terrain_splines.gd")

var splines: SplineTool = null
var foliage: FoliagePainter = null

var _dock: VBoxContainer = null
var _tabs: TabContainer = null
var _kind: OptionButton = null
var _width: SpinBox = null
var _radius: SpinBox = null
var _density: SpinBox = null
var _type_name: LineEdit = null
var _mode: OptionButton = null
var _status: Label = null
var _active_spline: int = -1
var _stroke: int = 0


func _enter_tree() -> void:
	var lib: GDScript = TerrainSplines
	if not lib.is_tool():
		push_warning("cgame_world_tools: shared terrain libraries are not @tool; editing inside the editor is limited.")
	splines = SplineTool.new()
	foliage = FoliagePainter.new()
	_dock = _build_dock()
	add_control_to_dock(DOCK_SLOT_LEFT_UR, _dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	splines = null
	foliage = null


func _build_dock() -> VBoxContainer:
	var root := VBoxContainer.new()
	root.name = "World Tools"
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(220, 260)
	root.add_child(_tabs)

	var sp := VBoxContainer.new()
	sp.name = "Splines"
	_tabs.add_child(sp)
	_kind = OptionButton.new()
	for k in SplineTool.KINDS:
		_kind.add_item(k)
	sp.add_child(_kind)
	_width = _spin(sp, "Width", 4.0, 0.5, 64.0)
	_button(sp, "New spline", _on_new_spline)
	_button(sp, "Delete last point", _on_delete_point)
	_button(sp, "Undo", func() -> void: _on_undo())
	_button(sp, "Redo", func() -> void: _on_redo())

	var fo := VBoxContainer.new()
	fo.name = "Foliage"
	_tabs.add_child(fo)
	_type_name = LineEdit.new()
	_type_name.text = "grass"
	_type_name.placeholder_text = "foliage type"
	fo.add_child(_type_name)
	_mode = OptionButton.new()
	_mode.add_item("Paint")
	_mode.add_item("Erase")
	fo.add_child(_mode)
	_radius = _spin(fo, "Radius", 5.0, 0.5, 100.0)
	_density = _spin(fo, "Density /m2", 0.5, 0.01, 20.0)

	_status = Label.new()
	root.add_child(_status)
	return root


func _spin(parent: Control, label: String, value: float, lo: float, hi: float) -> SpinBox:
	var l := Label.new()
	l.text = label
	parent.add_child(l)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.1
	s.value = value
	parent.add_child(s)
	return s


func _button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)


func _on_new_spline() -> void:
	_active_spline = splines.add_spline(_kind.get_item_text(_kind.selected), PackedVector3Array(), _width.value)
	_status.text = "Spline %d created" % _active_spline


func _on_delete_point() -> void:
	var n: int = splines.point_count(_active_spline)
	if n > 0:
		splines.delete_point(_active_spline, n - 1)


func _on_undo() -> void:
	if _tabs.current_tab == 0:
		splines.undo()
	else:
		foliage.undo()


func _on_redo() -> void:
	if _tabs.current_tab == 0:
		splines.redo()
	else:
		foliage.redo()


func _handles(object: Object) -> bool:
	return object is Node3D


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not (event is InputEventMouseButton):
		return AFTER_GUI_INPUT_PASS
	var mb: InputEventMouseButton = event
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed or _dock == null:
		return AFTER_GUI_INPUT_PASS
	var origin: Vector3 = camera.project_ray_origin(mb.position)
	var dir: Vector3 = camera.project_ray_normal(mb.position)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, dir)
	if hit == null:
		return AFTER_GUI_INPUT_PASS
	var p: Vector3 = hit
	if foliage.height_at.is_valid():
		p.y = float(foliage.height_at.call(p.x, p.z))
	if _tabs.current_tab == 0:
		if splines.get_spline(_active_spline).is_empty():
			_on_new_spline()
		splines.add_point(_active_spline, p)
	else:
		var t: String = _type_name.text
		_stroke += 1
		if _mode.selected == 0:
			foliage.paint(p, _radius.value, t, _density.value, _stroke)
		else:
			foliage.erase(p, _radius.value, t)
		_status.text = "%s: %d instances" % [t, foliage.count(t)]
	return AFTER_GUI_INPUT_STOP
