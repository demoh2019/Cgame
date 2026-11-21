extends RefCounted
## Runtime detection of optional native engine classes, so scripts run on older editor binaries too.
## Everything touching a custom class goes through ClassDB.instantiate / set / call, so scripts parse without it.


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


## Creates an engine class by name and applies properties; returns null when the binary lacks it.
static func make(engine_class: String, props: Dictionary = {}) -> Object:
	if not ClassDB.class_exists(engine_class):
		return null
	var obj: Object = ClassDB.instantiate(engine_class)
	if obj == null:
		return null
	for key in props:
		obj.set(key, props[key])
	return obj


## Radial physics push (RadialForceField3D) around a world position; false when the class is missing.
## Bodies on the ragdoll layer (1 << 19) are pushed by default.
static func radial_push(parent: Node, at: Vector3, radius: float, strength: float,
		upward: float = 0.4, mask: int = 1 << 19, wall_mask: int = 0,
		wall_attenuation: float = 0.25, velocity_change: bool = false,
		falloff_mode: int = 1) -> bool:
	var field := make("RadialForceField3D", {
		"radius": radius, "strength": strength, "falloff": falloff_mode, "upward_bias": upward,
		"collision_mask": mask, "free_after_fire": true}) as Node3D
	if field == null:
		return false
	# Some older fork binaries have RadialForceField3D but not the new
	# impulse/occlusion API. Fall back to the script implementation rather
	# than silently ignoring wall shielding or changing debris mass response.
	if (wall_mask != 0 or velocity_change) and (
			not field.has_method("set_occlusion_mask") or
			not field.has_method("set_mass_independent")):
		field.free()
		return false
	if wall_mask != 0:
		field.set("occlusion_mask", wall_mask)
		field.set("occlusion_attenuation", wall_attenuation)
		field.set("max_occlusion_rays", 24)
	if velocity_change:
		field.set("mass_independent", true)
	parent.add_child(field)
	field.global_position = at
	field.call("fire")
	return true
