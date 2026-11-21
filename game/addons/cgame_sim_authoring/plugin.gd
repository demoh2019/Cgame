@tool
extends EditorPlugin
## Adds a "Sim Authoring" dock exposing the fracture / cloth / hair authoring tools.
## Original code. Not enabled by default in project.godot.

var _dock: VBoxContainer
var _status: Label


func _enter_tree() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "Sim Authoring"
	_status = Label.new()
	_status.text = "Fracture / Cloth / Hair authoring (see addons/cgame_sim_authoring)"
	_dock.add_child(_status)
	var fracture_btn := Button.new()
	fracture_btn.text = "Preview fracture (box 2x2x2, 12 pieces)"
	fracture_btn.pressed.connect(_on_preview_fracture)
	_dock.add_child(fracture_btn)
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


func _on_preview_fracture() -> void:
	var FractureTool: GDScript = load("res://addons/cgame_sim_authoring/fracture_tool.gd")
	var tool_obj: RefCounted = FractureTool.new()
	var cells: Array = tool_obj.call("preview", Vector3(2, 2, 2), 12, 1, Vector3.INF, 0.0)
	_status.text = "Fracture preview: %d cells" % cells.size()
