@tool
extends EditorPlugin
## AI tools dock: planning debugger, spatial query graph editor and Smart Object placement.
## Not enabled by default; turn it on in Project Settings > Plugins. The shared libraries
## (ai_debug_recorder, spatial_query_graph) are @tool; utility_ai.gd / smart_objects.gd are not,
## so previews that call them inside the editor are limited (a warning is pushed).

const AIDebugPanel = preload("res://addons/cgame_ai_tools/ai_debug_panel.gd")
const QueryPanel = preload("res://addons/cgame_ai_tools/query_panel.gd")
const SmartObjectPanel = preload("res://addons/cgame_ai_tools/smart_object_panel.gd")
const UtilityAI = preload("res://scripts/shared/utility_ai.gd")

var debug_panel: AIDebugPanel = null
var query_panel: QueryPanel = null
var smart_panel: SmartObjectPanel = null

var _dock: TabContainer = null


func _enter_tree() -> void:
	var lib: GDScript = UtilityAI
	if not lib.is_tool():
		push_warning("cgame_ai_tools: utility_ai.gd / smart_objects.gd are not @tool; query scoring and auto place are limited inside the editor.")
	debug_panel = AIDebugPanel.new()
	debug_panel.name = "Planning"
	query_panel = QueryPanel.new()
	query_panel.name = "Queries"
	smart_panel = SmartObjectPanel.new()
	smart_panel.name = "Smart Objects"
	_dock = TabContainer.new()
	_dock.name = "Cgame AI"
	_dock.custom_minimum_size = Vector2(320, 300)
	_dock.add_child(debug_panel)
	_dock.add_child(query_panel)
	_dock.add_child(smart_panel)
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	debug_panel = null
	query_panel = null
	smart_panel = null
