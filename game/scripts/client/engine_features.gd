extends RefCounted
## Runtime detection of optional native engine classes, so scripts run on older editor binaries too.


static func has(engine_class: String) -> bool:
	return ClassDB.class_exists(engine_class)


## Tags a node with Gameplay Tags (meta "tags") when the engine provides GameplayTagContainer; a no-op otherwise.
static func tag_node(node: Node, tags: Array) -> void:
	if node == null or not has("GameplayTagContainer"):
		return
	var container = ClassDB.instantiate("GameplayTagContainer")
	for tag in tags:
		container.add_tag(StringName(str(tag)))
	node.set_meta("tags", container)
