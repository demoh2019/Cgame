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

## The native engine owns the live tag container. Snapshot states are read-only
## hints for visuals/tools; server combat authority is never inferred from tags.
static func runtime_tags(kind: String, state: Dictionary) -> PackedStringArray:
	var tags := PackedStringArray()
	if kind == "player":
		tags.append("Runtime.Life.Alive" if bool(state.get("alive", false)) else "Runtime.Life.Dead")
		if bool(state.get("mounted", false)):
			tags.append("Runtime.Movement.Mounted")
		if bool(state.get("crouching", false)):
			tags.append("Runtime.Movement.Crouching")
		if bool(state.get("outlaw", false)):
			tags.append("Runtime.Status.Outlaw")
		if bool(state.get("flare_lit", false)):
			tags.append("Runtime.Item.FlareLit")
	elif kind == "zombie":
		tags.append("Runtime.Life.Alive" if float(state.get("hp", 0.0)) > 0.0 else "Runtime.Life.Dead")
		if int(state.get("state", 0)) >= 2:
			tags.append("Runtime.Combat.Alert")
		if bool(state.get("elite", false)):
			tags.append("Runtime.Rank.Elite")
		if bool(state.get("raid_boss", false)):
			tags.append("Runtime.Rank.RaidBoss")
		if bool(state.get("raid_enraged", false)):
			tags.append("Runtime.Status.Enraged")
		if bool(state.get("melee_blocked", false)):
			tags.append("Runtime.Status.Blocked")
		if float(state.get("stagger_seconds", 0.0)) > 0.0:
			tags.append("Runtime.Status.Staggered")
		if float(state.get("snared_seconds", 0.0)) > 0.0:
			tags.append("Runtime.Status.Snared")
		if float(state.get("sunder_seconds", 0.0)) > 0.0:
			tags.append("Runtime.Status.Sundered")
		if int(state.get("resolve_stacks", 0)) >= 2 and float(state.get("resolve_seconds", 0.0)) > 0.0:
			tags.append("Runtime.Status.Resolve")
	return tags


## Replaces one namespace atomically, preserving static Enemy/Player identity.
## Old engine binaries simply retain the established rendering paths.
static func sync_runtime_tags(node: Node, kind: String, snapshot: Dictionary) -> void:
	if node == null or not node.has_meta("tags"):
		return
	var container: Object = node.get_meta("tags") as Object
	if container != null and container.has_method("replace_tag_branch"):
		container.call("replace_tag_branch", StringName("Runtime"), runtime_tags(kind, snapshot))


## Counts independently active crowd-control statuses from server snapshots.
## The custom engine uses native matching; older binaries read the same
## authoritative snapshot fields, never user-supplied tags.
static func zombie_control_count(node: Node, snapshot: Dictionary) -> int:
	if node != null and node.has_meta("tags"):
		var container: Object = node.get_meta("tags") as Object
		if container != null and container.has_method("count_matching_queries"):
			return int(container.call("count_matching_queries", PackedStringArray([
				"Runtime.Status.Staggered", "Runtime.Status.Snared", "Runtime.Status.Sundered"]), true))
	return int(float(snapshot.get("stagger_seconds", 0.0)) > 0.0) \
		+ int(float(snapshot.get("snared_seconds", 0.0)) > 0.0) \
		+ int(float(snapshot.get("sunder_seconds", 0.0)) > 0.0)


static func runtime_has(node: Node, tag: String, fallback: bool = false) -> bool:
	if node != null and node.has_meta("tags"):
		var container: Object = node.get_meta("tags") as Object
		if container != null and container.has_method("replace_tag_branch") and container.has_method("has_tag"):
			return bool(container.call("has_tag", StringName(tag), true))
	return fallback
