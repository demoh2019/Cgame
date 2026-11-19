@tool
extends VBoxContainer
## Minimal GraphEdit UI for loading, editing, and saving PCGGraph resources.

var _graph: PCGGraph
var _graph_edit: GraphEdit
var _path: LineEdit
var _status: Label
var _type_select: OptionButton


func _ready() -> void:
	custom_minimum_size = Vector2(720, 250)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var file_bar := HBoxContainer.new()
	add_child(file_bar)
	_path = LineEdit.new()
	_path.placeholder_text = "res://world_graph.tres"
	_path.text = "res://world_graph.tres"
	_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_bar.add_child(_path)
	for label in ["New", "Open", "Save"]:
		var button := Button.new()
		button.text = label
		file_bar.add_child(button)
		match label:
			"New":
				button.pressed.connect(_new_graph)
			"Open":
				button.pressed.connect(_open_graph)
			"Save":
				button.pressed.connect(_save_graph)

	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	_type_select = OptionButton.new()
	for kind in PCGGraph.NODE_KINDS:
		_type_select.add_item(kind)
	toolbar.add_child(_type_select)

	var add_button := Button.new()
	add_button.text = "Add node"
	toolbar.add_child(add_button)
	add_button.pressed.connect(_add_node)

	var generate_button := Button.new()
	generate_button.text = "Generate on selected PCGSpawner3D"
	toolbar.add_child(generate_button)
	generate_button.pressed.connect(_generate_selected)

	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_status)

	_graph_edit = GraphEdit.new()
	_graph_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph_edit.connection_request.connect(_request_connection)
	_graph_edit.disconnection_request.connect(_request_disconnection)
	_graph_edit.delete_nodes_request.connect(_request_deletions)
	add_child(_graph_edit)
	_new_graph()


func _set_status(message: String) -> void:
	_status.text = message


func _new_graph() -> void:
	_graph = PCGGraph.make_default()
	_set_status("New graph (not yet saved)")
	_rebuild()


func _open_graph() -> void:
	var path := _path.text.strip_edges()
	if not path.begins_with("res://") or not path.ends_with(".tres"):
		_set_status("Open requires a res://*.tres resource")
		return
	var loaded := load(path) as PCGGraph
	if loaded == null:
		_set_status("Not a PCGGraph: %s" % path)
		return
	_graph = loaded
	_set_status("Opened %s" % path)
	_rebuild()


func _save_graph() -> void:
	var path := _path.text.strip_edges()
	if not path.begins_with("res://") or not path.ends_with(".tres"):
		_set_status("Save requires a res://*.tres resource")
		return
	var error := ResourceSaver.save(_graph, path)
	if error == OK:
		_graph.take_over_path(path)
		_set_status("Saved %s" % path)
	else:
		_set_status("Save failed (%s)" % error)


func _add_node() -> void:
	var kind := _type_select.get_item_text(_type_select.selected)
	var position := Vector2(80 + _graph.nodes.size() * 45, 90 + _graph.nodes.size() * 25)
	if _graph.add_graph_node(kind, position) == -1:
		_set_status("Cannot add more nodes")
	else:
		_set_status("Added %s" % kind)
		_rebuild()


func _node_name(node_id: int) -> StringName:
	return StringName("PCG_%d" % node_id)


func _node_id(node_name: StringName) -> int:
	var value := String(node_name)
	if not value.begins_with("PCG_"):
		return -1
	return value.trim_prefix("PCG_").to_int()


func _make_parameter(parent: GraphNode, node_id: int, key: String, value: Variant) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = key
	label.custom_minimum_size.x = 80
	row.add_child(label)
	var spin := SpinBox.new()
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.min_value = -100000.0
	spin.max_value = 100000.0
	spin.step = 0.01
	if key in ["columns", "rows"]:
		spin.min_value = 1
		spin.max_value = 10000
		spin.step = 1
	elif key == "chance":
		spin.min_value = 0.0
		spin.max_value = 1.0
		spin.step = 0.01
	elif key in ["spacing", "minimum_distance"]:
		spin.min_value = 0.001
	elif key == "frequency":
		spin.min_value = 0.000001
		spin.step = 0.0001
	elif key in ["radius", "amplitude"]:
		spin.min_value = 0.0
	spin.value = float(value)
	spin.value_changed.connect(_parameter_changed.bind(node_id, key))
	row.add_child(spin)


func _parameter_changed(value: float, node_id: int, key: String) -> void:
	if _graph == null:
		return
	var entry := _graph.get_graph_node(node_id)
	if entry.is_empty():
		return
	var params: Dictionary = entry["params"]
	params[key] = int(value) if key in ["columns", "rows"] else value
	_graph.update_parameters(node_id, params)


func _add_visual_node(entry: Dictionary) -> void:
	var id: int = entry["id"]
	var kind: String = entry["kind"]
	var widget := GraphNode.new()
	widget.name = _node_name(id)
	widget.title = "%s #%d" % [kind, id]
	widget.position_offset = entry.get("position", Vector2.ZERO)
	widget.show_close = true
	widget.close_request.connect(_remove_node.bind(id))
	widget.position_offset_changed.connect(_position_changed.bind(id))

	var row := HBoxContainer.new()
	var port_label := Label.new()
	port_label.text = "Points" if kind != "GRID" else "Generate points"
	row.add_child(port_label)
	widget.add_child(row)
	widget.set_slot(0, kind != "GRID", 0, Color(0.4, 0.7, 1.0),
			kind != "OUTPUT", 0, Color(0.4, 0.7, 1.0))
	var params: Dictionary = entry["params"]
	for key in params:
		_make_parameter(widget, id, key, params[key])
	_graph_edit.add_child(widget)


func _rebuild() -> void:
	if _graph_edit == null or _graph == null:
		return
	_graph_edit.clear_connections()
	for child in _graph_edit.get_children():
		if child is GraphNode:
			_graph_edit.remove_child(child)
			child.queue_free()
	for entry in _graph.nodes:
		_add_visual_node(entry)
	for edge in _graph.connections:
		var source := _node_name(int(edge["from"]))
		var target := _node_name(int(edge["to"]))
		_graph_edit.connect_node(source, 0, target, 0)


func _request_connection(from_node: StringName, from_port: int,
		to_node: StringName, to_port: int) -> void:
	if from_port != 0 or to_port != 0:
		return
	if not _graph.add_connection(_node_id(from_node), _node_id(to_node)):
		_set_status("Connection rejected (cycle, duplicate or incompatible ports)")
		return
	_set_status("Connected")
	_rebuild()


func _request_disconnection(from_node: StringName, from_port: int,
		to_node: StringName, to_port: int) -> void:
	if from_port != 0 or to_port != 0:
		return
	_graph.remove_connection(_node_id(from_node), _node_id(to_node))
	_rebuild()


func _remove_node(node_id: int) -> void:
	_graph.remove_graph_node(node_id)
	_rebuild()


func _request_deletions(node_names: Array[StringName]) -> void:
	for name in node_names:
		_graph.remove_graph_node(_node_id(name))
	_rebuild()


func _position_changed(node_id: int) -> void:
	var widget := _graph_edit.get_node_or_null(NodePath(_node_name(node_id))) as GraphNode
	if widget != null:
		_graph.set_node_position(node_id, widget.position_offset)


func _generate_selected() -> void:
	var selected := EditorInterface.get_selection().get_selected_nodes()
	for node in selected:
		if node is PCGSpawner3D:
			node.graph = _graph
			if node.generate():
				_set_status("Generated %d instances" % node.get_generated_count())
			else:
				_set_status("Generation failed; inspect warnings")
			return
	_set_status("Select a PCGSpawner3D and assign its instance_mesh")
