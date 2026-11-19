@tool
extends VBoxContainer
class_name OWPCGGraphDock
## Small GraphEdit authoring surface for OWPCGGraph. The resource is saved in the scene.

signal bake_requested

const KIND_NAMES := ["Constant", "Noise", "Add", "Multiply", "Clamp", "Terrace", "Output"]
const PARAMETERS := {
	"Constant": ["value"],
	"Noise": ["frequency", "amplitude"],
	"Clamp": ["minimum", "maximum"],
	"Terrace": ["steps"],
}

var terrain: OWTerrain3D
var graph: OWPCGGraph
var diagram: GraphEdit
var kind_choice: OptionButton
var property_container: VBoxContainer
var status: Label
var selected_id: int = -1
var _syncing: bool = false


func _ready() -> void:
	name = "World PCG"
	var heading := Label.new()
	heading.text = "Procedural Terrain Graph"
	add_child(heading)
	var buttons := HBoxContainer.new()
	add_child(buttons)
	var create := Button.new()
	create.text = "New graph"
	create.pressed.connect(_new_graph)
	buttons.add_child(create)
	kind_choice = OptionButton.new()
	for kind in KIND_NAMES:
		kind_choice.add_item(kind)
	buttons.add_child(kind_choice)
	var add := Button.new()
	add.text = "Add node"
	add.pressed.connect(_add_node)
	buttons.add_child(add)
	var bake_button := Button.new()
	bake_button.text = "Bake to Terrain (Undoable)"
	bake_button.pressed.connect(func(): bake_requested.emit())
	add_child(bake_button)
	diagram = GraphEdit.new()
	diagram.custom_minimum_size = Vector2(320.0, 310.0)
	diagram.size_flags_vertical = Control.SIZE_EXPAND_FILL
	diagram.connection_request.connect(_connect_requested)
	diagram.disconnection_request.connect(_disconnect_requested)
	diagram.delete_nodes_request.connect(_delete_requested)
	diagram.node_selected.connect(_node_selected)
	add_child(diagram)
	property_container = VBoxContainer.new()
	add_child(property_container)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	_refresh()


func set_terrain(value: OWTerrain3D) -> void:
	terrain = value
	graph = terrain.pcg_graph if terrain != null else null
	selected_id = -1
	if is_node_ready():
		_refresh()


func _new_graph() -> void:
	if terrain == null:
		status.text = "Select a terrain node first."
		return
	graph = OWPCGGraph.make_default_graph()
	terrain.pcg_graph = graph
	EditorInterface.mark_scene_as_unsaved()
	selected_id = -1
	_refresh()


func _add_node() -> void:
	if graph == null:
		status.text = "Create a graph first."
		return
	var kind := KIND_NAMES[kind_choice.selected]
	var id := graph.add_node(kind, Vector2(90.0 + float(graph.nodes.size() % 3) * 160.0, 90.0 + floorf(float(graph.nodes.size()) / 3.0) * 110.0))
	if id == -1:
		status.text = "Only one Output node is allowed."
		return
	selected_id = id
	EditorInterface.mark_scene_as_unsaved()
	_refresh()


func _connect_requested(from_name: StringName, _from_port: int, to_name: StringName, to_port: int) -> void:
	if graph == null:
		return
	if graph.connect_nodes(int(from_name), int(to_name), to_port):
		EditorInterface.mark_scene_as_unsaved()
		_refresh()
	else:
		status.text = "Invalid connection: check port type or graph cycle."


func _disconnect_requested(from_name: StringName, _from_port: int, to_name: StringName, to_port: int) -> void:
	if graph != null and graph.disconnect_nodes(int(from_name), int(to_name), to_port):
		EditorInterface.mark_scene_as_unsaved()
		_refresh()


func _delete_requested(names: Array[StringName]) -> void:
	if graph == null:
		return
	var removed := false
	for name_in_graph in names:
		removed = graph.remove_node(int(name_in_graph)) or removed
	if removed:
		selected_id = -1
		EditorInterface.mark_scene_as_unsaved()
		_refresh()


func _node_selected(node: Node) -> void:
	selected_id = int(node.name)
	_update_properties()


func _moved(id: int, node: GraphNode) -> void:
	if not _syncing and graph != null and graph.set_node_position(id, node.position_offset):
		EditorInterface.mark_scene_as_unsaved()


func _refresh() -> void:
	if diagram == null or status == null:
		return
	_syncing = true
	diagram.clear_connections()
	for node in diagram.get_children():
		if node is GraphNode:
			diagram.remove_child(node)
			node.queue_free()
	if graph != null:
		for entry in graph.nodes:
			var id := int(entry.get("id", -1))
			var kind := str(entry.get("kind", ""))
			var visual := GraphNode.new()
			visual.name = str(id)
			visual.title = kind + " #" + str(id)
			visual.position_offset = entry.get("position", Vector2.ZERO)
			var inputs := int(OWPCGGraph.INPUT_COUNTS.get(kind, 0))
			for slot in maxi(inputs, 1):
				var label := Label.new()
				label.text = "In " + str(slot) if slot < inputs else "Value"
				visual.add_child(label)
				visual.set_slot(slot, slot < inputs, 0, Color.WHITE, slot == 0 and kind != "Output", 0, Color.WHITE)
			visual.position_offset_changed.connect(_moved.bind(id, visual))
			diagram.add_child(visual)
		for link in graph.links:
			diagram.connect_node(str(link["from"]), 0, str(link["to"]), int(link["input"]))
	_syncing = false
	_update_properties()
	if terrain == null:
		status.text = "Select an OWTerrain3D node."
	elif graph == null:
		status.text = "Select New graph to create an editable PCG resource."
	else:
		var problem := graph.validation_error()
		status.text = "Ready: graph can be baked." if problem.is_empty() else "Graph incomplete: " + problem


func _update_properties() -> void:
	if property_container == null:
		return
	for child in property_container.get_children():
		property_container.remove_child(child)
		child.queue_free()
	if graph == null:
		return
	var entry := graph.get_node_data(selected_id)
	if entry.is_empty():
		return
	var kind := str(entry.get("kind", ""))
	var names: Array = PARAMETERS.get(kind, [])
	var params: Dictionary = entry.get("params", {})
	for key in names:
		var row := HBoxContainer.new()
		var title := Label.new()
		title.text = str(key)
		row.add_child(title)
		var spin := SpinBox.new()
		spin.min_value = -1000000.0
		spin.max_value = 1000000.0
		spin.step = 0.01
		if key == "frequency":
			spin.min_value = 0.000001
			spin.step = 0.005
		if key == "steps":
			spin.min_value = 1.0
			spin.max_value = 256.0
			spin.step = 1.0
		spin.value = float(params.get(key, 0.0))
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.value_changed.connect(_parameter_changed.bind(selected_id, str(key)))
		row.add_child(spin)
		property_container.add_child(row)


func _parameter_changed(value: float, id: int, key: String) -> void:
	if graph != null and graph.set_parameter(id, key, value):
		EditorInterface.mark_scene_as_unsaved()