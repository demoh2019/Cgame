@tool
extends Node3D
class_name PCGSpawner3D
## Generates a GPU-instanced MultiMesh from a PCGGraph's OUTPUT points.

const GENERATED_NAME := "_PCGGenerated"

@export var graph: PCGGraph
@export var instance_mesh: Mesh
@export_range(1, 10000, 1) var max_instances: int = 10000
@export var generate_on_game_start: bool = false
@export_tool_button("Generate PCG", "Callable") var generate_action = generate
@export_tool_button("Clear PCG", "Callable") var clear_action = clear_generated


func _ready() -> void:
	if not Engine.is_editor_hint() and generate_on_game_start:
		generate()


func get_generated_count() -> int:
	var generated := get_node_or_null(GENERATED_NAME) as MultiMeshInstance3D
	if generated == null or generated.multimesh == null:
		return 0
	return generated.multimesh.instance_count


func clear_generated() -> void:
	var generated := get_node_or_null(GENERATED_NAME)
	if generated != null:
		remove_child(generated)
		generated.queue_free()


func generate() -> bool:
	# Validate before destroying the last successful generation.
	if graph == null or instance_mesh == null:
		push_warning("PCGSpawner3D needs a PCGGraph and an instance_mesh.")
		return false
	var generated_data := PCGGenerator.evaluate(graph)
	if not generated_data["ok"]:
		push_warning("PCG evaluation failed: %s" % generated_data["error"])
		return false
	var points: Array = generated_data["points"]
	if points.size() > max_instances:
		push_warning("PCG would create %d instances; limit is %d." % [points.size(), max_instances])
		return false

	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = instance_mesh
	instances.instance_count = points.size()
	for i in points.size():
		instances.set_instance_transform(i, Transform3D(Basis.IDENTITY, points[i]))

	var new_node := MultiMeshInstance3D.new()
	new_node.name = GENERATED_NAME
	new_node.multimesh = instances
	clear_generated()
	add_child(new_node)
	# Save generated instances even when this spawner is the edited scene root.
	if Engine.is_editor_hint() and get_tree() != null:
		var edited_root := get_tree().edited_scene_root
		if edited_root != null and (edited_root == self or edited_root.is_ancestor_of(self)):
			new_node.owner = edited_root
	return true
