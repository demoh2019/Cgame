extends RefCounted
## Converts SceneTree nodes into entities of the MassEntity runtime (scripts/shared/mass_entity.gd).
##
## A rule is a Dictionary:
##   group: StringName   match nodes in this group (optional)
##   script: Script      match nodes with exactly this script (optional)
##   meta: StringName    match nodes that have this meta key (optional)
##   map: Dictionary     fragment name -> node property (e.g. {"pos": "position", "hp": "health"})
##   action: String      "keep" (default), "hide" (Node3D/CanvasItem visible = false) or "free"
## The first rule that matches a node wins. Fragment types are inferred from the property value
## (Vector3 -> PACKED_VECTOR3, float -> PACKED_FLOAT32, int/bool -> PACKED_INT32); unsupported
## property types are skipped. Concepts only (original GDScript): Unreal "Mass" actor-to-entity
## conversion and Unity DOTS baking.

const MassEntity = preload("res://scripts/shared/mass_entity.gd")


static func _matches(node: Node, rule: Dictionary) -> bool:
	var has_criterion := false
	if rule.has("group"):
		has_criterion = true
		if not node.is_in_group(StringName(rule["group"])):
			return false
	if rule.has("script"):
		has_criterion = true
		if node.get_script() != rule["script"]:
			return false
	if rule.has("meta"):
		has_criterion = true
		if not node.has_meta(StringName(rule["meta"])):
			return false
	return has_criterion


static func _collect(node: Node, out: Array[Node]) -> void:
	out.append(node)
	for c in node.get_children():
		_collect(c, out)


static func _fragment_type(v: Variant) -> int:
	match typeof(v):
		TYPE_VECTOR3:
			return TYPE_PACKED_VECTOR3_ARRAY
		TYPE_FLOAT:
			return TYPE_PACKED_FLOAT32_ARRAY
		TYPE_INT, TYPE_BOOL:
			return TYPE_PACKED_INT32_ARRAY
	return -1


static func _to_fragment(v: Variant) -> Variant:
	if v is bool:
		return 1 if v else 0
	return v


## Returns {mass, mapping, converted, freed, skipped}. mapping entries are
## {node, id, map, action}; `node` is null once the node has been freed.
static func convert(root: Node, rules: Array, mass: MassEntity = null) -> Dictionary:
	var world: MassEntity = mass if mass != null else MassEntity.new()
	var nodes: Array[Node] = []
	_collect(root, nodes)
	var mapping: Array = []
	var skipped := 0
	var freed := 0
	for node in nodes:
		var rule: Dictionary = {}
		for r in rules:
			if _matches(node, r):
				rule = r
				break
		if rule.is_empty():
			continue
		var map: Dictionary = rule.get("map", {})
		var frags: Dictionary = {}
		var used: Dictionary = {}
		for fname in map:
			var prop: String = map[fname]
			var raw: Variant = node.get(prop)
			var ftype := _fragment_type(raw)
			if ftype < 0:
				continue
			world.define_fragment(str(fname), ftype)
			frags[str(fname)] = _to_fragment(raw)
			used[str(fname)] = prop
		if frags.is_empty():
			skipped += 1
			continue
		var id := world.create(frags)
		if id < 0:
			skipped += 1
			continue
		var action: String = rule.get("action", "keep")
		var entry := {"node": node, "id": id, "map": used, "action": action}
		match action:
			"hide":
				if "visible" in node:
					node.set("visible", false)
			"free":
				if node != root:
					entry["node"] = null
					freed += 1
					if node.is_inside_tree():
						node.queue_free()
					else:
						node.free()
		mapping.append(entry)
	return {"mass": world, "mapping": mapping, "converted": mapping.size(), "freed": freed, "skipped": skipped}


## Writes fragment values back to the remaining (not freed) nodes. Returns nodes updated.
static func sync_back(mass: MassEntity, mapping: Array) -> int:
	var n := 0
	for entry in mapping:
		var node: Variant = entry["node"]
		if node == null or not is_instance_valid(node):
			continue
		var id: int = entry["id"]
		if not mass.is_alive(id):
			continue
		var map: Dictionary = entry["map"]
		for fname in map:
			var v: Variant = mass.get_value(id, str(fname))
			if v == null:
				continue
			var prop: String = map[fname]
			var cur: Variant = (node as Object).get(prop)
			if cur is bool:
				v = int(v) != 0
			(node as Object).set(prop, v)
		n += 1
	return n


## Suggests where to keep `count` objects. access_pattern: "iterate" (bulk per-frame passes),
## "random" (lookup by identity), "sparse" (few active of many) or "mixed".
## Returns "node", "mass_soa" (archetype chunks, best for bulk iteration) or "mass_sparse".
static func choose_storage(count: int, access_pattern: String) -> String:
	if count < 32:
		return "node"
	match access_pattern:
		"iterate":
			return "mass_soa"
		"sparse":
			return "mass_sparse" if count >= 1024 else "node"
		"random":
			return "node" if count < 4096 else "mass_soa"
		_:
			return "mass_soa" if count >= 512 else "node"
