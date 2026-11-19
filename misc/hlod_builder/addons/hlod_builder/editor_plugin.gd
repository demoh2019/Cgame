@tool
extends EditorPlugin

var _panel: VBoxContainer
var _status: Label


func _enter_tree() -> void:
	_panel = VBoxContainer.new()
	_panel.name = "HLOD Builder"
	_panel.custom_minimum_size = Vector2(190, 90)

	var title := Label.new()
	title.text = "HLOD cluster tools"
	_panel.add_child(title)

	var build_button := Button.new()
	build_button.text = "Build selected cluster"
	build_button.pressed.connect(_build_selected)
	_panel.add_child(build_button)

	var clear_button := Button.new()
	clear_button.text = "Clear selected proxy"
	clear_button.pressed.connect(_clear_selected)
	_panel.add_child(clear_button)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_status)
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _panel)


func _exit_tree() -> void:
	if is_instance_valid(_panel):
		remove_control_from_docks(_panel)
		_panel.queue_free()
	_panel = null
	_status = null


func _selected_cluster() -> HLODCluster3D:
	var selection := EditorInterface.get_selection().get_selected_nodes()
	for item in selection:
		if item is HLODCluster3D:
			return item
	return null


func _build_selected() -> void:
	var cluster := _selected_cluster()
	if cluster == null:
		_status.text = "Select an HLODCluster3D in the Scene tree."
		return
	if cluster.build_proxy():
		_status.text = "Built %d proxy vertices, %d material surfaces." % [
				cluster.get_proxy_vertex_count(), cluster.get_proxy_surface_count()]
	else:
		_status.text = "Cannot build this cluster. See Output warnings."


func _clear_selected() -> void:
	var cluster := _selected_cluster()
	if cluster == null:
		_status.text = "Select an HLODCluster3D."
		return
	cluster.clear_proxy()
	_status.text = "Removed generated HLOD proxy."
