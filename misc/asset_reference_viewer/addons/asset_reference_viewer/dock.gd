@tool
extends VBoxContainer
## Opt-in inspector. Does not open, execute, or modify referenced assets.

const GraphIndex = preload("res://addons/asset_reference_viewer/graph_index.gd")

var _path: LineEdit
var _direction: OptionButton
var _depth: SpinBox
var _status: Label
var _result: Tree
var _graph: Dictionary = {}
var _trace: Dictionary = {}
var _dirty := true


func _ready() -> void:
	custom_minimum_size = Vector2(360, 250)
	var title := Label.new()
	title.text = "Asset Reference Viewer"
	add_child(title)

	var choose := Button.new()
	choose.text = "Use selected file in FileSystem"
	choose.pressed.connect(_use_file_system_selection)
	add_child(choose)

	_path = LineEdit.new()
	_path.placeholder_text = "res://scenes/main.tscn"
	_path.text_submitted.connect(func(_text: String) -> void: _render())
	add_child(_path)

	var filters := HBoxContainer.new()
	add_child(filters)
	_direction = OptionButton.new()
	_direction.add_item("Both directions")
	_direction.add_item("Dependencies")
	_direction.add_item("Referenced by")
	_direction.item_selected.connect(func(_item: int) -> void: _render())
	filters.add_child(_direction)
	_depth = SpinBox.new()
	_depth.min_value = -1
	_depth.max_value = 32
	_depth.value = 1
	_depth.step = 1
	_depth.tooltip_text = "Reference hops; -1 traverses all reachable files"
	_depth.value_changed.connect(func(_value: float) -> void: _render())
	filters.add_child(_depth)

	var buttons := HBoxContainer.new()
	add_child(buttons)
	var refresh := Button.new()
	refresh.text = "Refresh index"
	refresh.pressed.connect(_refresh_index)
	buttons.add_child(refresh)
	var copy := Button.new()
	copy.text = "Copy DOT"
	copy.tooltip_text = "Copy Graphviz DOT for the currently displayed graph"
	copy.pressed.connect(_copy_dot)
	buttons.add_child(copy)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Choose a resource and click Refresh index."
	add_child(_status)

	_result = Tree.new()
	_result.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_result.columns = 3
	_result.hide_root = true
	_result.set_column_title(0, "Referrer")
	_result.set_column_title(1, "Dependency")
	_result.set_column_title(2, "Line")
	_result.set_column_titles_visible(true)
	_result.set_column_expand(2, false)
	_result.set_column_custom_minimum_width(2, 48)
	_result.item_activated.connect(_browse_selected_source)
	add_child(_result)


func invalidate_index() -> void:
	_dirty = true
	if is_instance_valid(_status):
		_status.text = "Project files changed. Click Refresh index to rescan."


func _use_file_system_selection() -> void:
	var selected := EditorInterface.get_selected_paths()
	if selected.is_empty():
		_status.text = "Select a file in the editor FileSystem first."
		return
	_path.text = selected[0]
	_render()


func _refresh_index() -> void:
	_graph = GraphIndex.build_project()
	_dirty = false
	_render()


func _render() -> void:
	if not is_instance_valid(_result):
		return
	_result.clear()
	_trace = {}
	if _dirty or _graph.is_empty():
		_status.text = "Click Refresh index to scan project references."
		return
	var asset := _path.text.strip_edges()
	if asset.is_empty():
		_status.text = "Enter res:// path or select a file in FileSystem."
		return
	var direction := "both"
	if _direction.selected == 1:
		direction = "dependencies"
	elif _direction.selected == 2:
		direction = "referencers"
	_trace = GraphIndex.trace(_graph, asset, direction, int(_depth.value))
	if not _trace["error"].is_empty():
		_status.text = _trace["error"]
		return
	var root := _result.create_item()
	for reference in _trace["references"]:
		var item := _result.create_item(root)
		var source := "res://" + reference["source"]
		var target := "res://" + reference["target"]
		item.set_text(0, source)
		item.set_text(1, target)
		item.set_text(2, str(reference["line"]))
		item.set_metadata(0, source)
		item.set_metadata(1, target)
	if _trace["references"].is_empty():
		var empty := _result.create_item(root)
		empty.set_text(0, "No static references found")
	var suffix := ""
	if not _graph["errors"].is_empty():
		suffix = " | Scan warnings: " + str(_graph["errors"].size())
	_status.text = "%d assets, %d references%s" % [_trace["nodes"].size(), _trace["references"].size(), suffix]


func _copy_dot() -> void:
	if _trace.is_empty() or _trace.get("error", "") != "":
		_status.text = "Select and inspect an asset before copying."
		return
	DisplayServer.clipboard_set(GraphIndex.to_dot(_trace))


func _browse_selected_source() -> void:
	var item := _result.get_selected()
	if item == null:
		return
	var path: String = item.get_metadata(0) if item.get_metadata(0) is String else ""
	if path.begins_with("res://"):
		EditorInterface.get_file_system_dock().navigate_to_path(path)
