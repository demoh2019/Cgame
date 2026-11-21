@tool
extends EditorPlugin
## "World Partition" dock. Collects Node3D actors of the edited scene that carry
## metadata `wp_layers` (PackedStringArray/Array), `wp_guid` (String) and
## `wp_spatially_loaded` (bool) and bakes them with world_partition_bake.gd.
## Concepts follow the public Unreal Engine World Partition docs; original code.

const WPPanel = preload("res://addons/cgame_world_partition/world_partition_panel.gd")

var _panel: Control


func _enter_tree() -> void:
	_panel = WPPanel.new()
	_panel.name = "World Partition"
	_panel.custom_minimum_size = Vector2(420, 360)
	_panel.collect_requested.connect(_collect_and_bake)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _panel)


func _exit_tree() -> void:
	if _panel != null:
		remove_control_from_docks(_panel)
		_panel.queue_free()
		_panel = null


func _collect_and_bake() -> void:
	var root: Node = get_editor_interface().get_edited_scene_root()
	if root == null or _panel == null:
		return
	_panel.set_actors(collect_actors(root))
	_panel.bake(_panel.cell_size)


## Public so tools/tests can reuse the scene scan.
func collect_actors(root: Node) -> Array:
	var out: Array = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is Node3D):
			continue
		if not (n.has_meta("wp_layers") or n.has_meta("wp_guid") or n.has_meta("wp_spatially_loaded")):
			continue
		var n3: Node3D = n
		var layers: PackedStringArray = PackedStringArray(n3.get_meta("wp_layers", PackedStringArray()))
		out.append({
			"guid": String(n3.get_meta("wp_guid", "")),
			"position": n3.global_position,
			"layers": layers,
			"spatially_loaded": bool(n3.get_meta("wp_spatially_loaded", true)),
			"data": {"name": String(n3.name)},
		})
	return out
