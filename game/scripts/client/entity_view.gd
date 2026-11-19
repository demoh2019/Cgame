extends Node3D
## Draws the moving things: other players, zombies and loot bags, smoothed between snapshots.

const Defs = preload("res://scripts/shared/defs.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const Meshes = preload("res://scripts/client/meshes.gd")
const CharacterModel = preload("res://scripts/client/character_model.gd")

const ZOMBIE_LOOK := {
	"walker": {"tint": Color(0.62, 0.85, 0.55), "scale": 2.0, "walk": 0.8},
	"runner": {"tint": Color(0.9, 0.9, 0.45), "scale": 1.85, "walk": 1.8},
	"brute": {"tint": Color(0.55, 0.5, 0.7), "scale": 3.0, "walk": 0.7},
}
const ALERT_TINT := Color(1.0, 0.45, 0.4)

var _nodes: Dictionary = {} # "kind:id" -> Node3D
var _targets: Dictionary = {} # "kind:id" -> {"position": Vector3, "yaw": float}


func update_from(client) -> void:
	var seen: Dictionary = {}
	for id in client.players:
		_touch("player:%d" % id, "player", client.players[id], seen)
	for id in client.zombies:
		_touch("zombie:%d" % id, "zombie", client.zombies[id], seen)
	for id in client.bags:
		_touch("bag:%d" % id, "bag", client.bags[id], seen)
	for id in client.barricades:
		_touch("barricade:%d" % id, "barricade", client.barricades[id], seen)
	for id in client.campfires:
		_touch("campfire:%d" % id, "campfire", client.campfires[id], seen)
	for key in _nodes.keys():
		if not seen.has(key):
			_nodes[key].queue_free()
			_nodes.erase(key)
			_targets.erase(key)


func _touch(key: String, kind: String, entity: Dictionary, seen: Dictionary) -> void:
	seen[key] = true
	if not _nodes.has(key):
		_nodes[key] = _make(kind, entity)
		add_child(_nodes[key])
		_nodes[key].position = Vector3(entity["x"], entity["y"], entity["z"])
	_targets[key] = {"position": Vector3(entity["x"], entity["y"], entity["z"]), "yaw": float(entity.get("yaw", 0.0))}
	var label: Label3D = _nodes[key].get_node_or_null("Label")
	if label != null:
		if kind == "zombie":
			label.text = "%s%s  %d" % [
				"RAID BOSS " if bool(entity.get("raid_boss", false)) else ("ELITE " if bool(entity.get("elite", false)) else ""),
				str(entity["type"]), int(entity["hp"])]
		elif kind == "player":
			label.text = str(entity["name"]) if entity["alive"] else "%s (dead)" % entity["name"]
	if kind == "barricade":
		var barricade_mesh: MeshInstance3D = _nodes[key].get_child(0)
		var barricade_material: StandardMaterial3D = barricade_mesh.material_override
		var tier: int = Structures.tier_of(entity)
		var fraction: float = clampf(float(entity.get("hp", 0.0)) / maxf(1.0, Structures.max_health(tier)), 0.0, 1.0)
		barricade_material.albedo_color = Color(0.20, 0.18, 0.18).lerp(Structures.color_for_tier(tier), fraction)
	if kind == "zombie":
		# A zombie that has locked on to someone flushes red.
		var model: Node3D = _nodes[key].get_node("Model")
		var base: Color = ZOMBIE_LOOK[entity["type"]]["tint"]
		if bool(entity.get("raid_boss", false)):
			base = Color(0.92, 0.2, 0.63)
		elif bool(entity.get("elite", false)):
			base = Color(0.98, 0.65, 0.18)
		model.set_tint(base.lerp(ALERT_TINT, 0.45) if int(entity["state"]) >= 2 else base)
	if kind == "player":
		_nodes[key].get_node("Model").visible = bool(entity["alive"])


func _make(kind: String, entity: Dictionary) -> Node3D:
	var root := Node3D.new()
	if kind == "barricade":
		var barricade := MeshInstance3D.new()
		var barrier := BoxMesh.new()
		barrier.size = Vector3(1.7, 1.6, 1.7)
		barricade.mesh = barrier
		barricade.position.y = 0.8
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.6, 0.45, 0.27)
		barricade.material_override = material
		root.add_child(barricade)
		return root
	if kind == "campfire":
		var wood := MeshInstance3D.new()
		var wood_mesh := CylinderMesh.new()
		wood_mesh.top_radius = 0.42
		wood_mesh.bottom_radius = 0.5
		wood_mesh.height = 0.22
		wood.mesh = wood_mesh
		wood.position.y = 0.13
		var wood_material := StandardMaterial3D.new()
		wood_material.albedo_color = Color(0.32, 0.18, 0.09)
		wood.material_override = wood_material
		root.add_child(wood)
		var flame := MeshInstance3D.new()
		var fire_mesh := SphereMesh.new()
		fire_mesh.radius = 0.34
		fire_mesh.height = 0.7
		flame.mesh = fire_mesh
		flame.position.y = 0.57
		var fire_material := StandardMaterial3D.new()
		fire_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fire_material.albedo_color = Color(1.0, 0.42, 0.08)
		flame.material_override = fire_material
		root.add_child(flame)
		var light := OmniLight3D.new()
		light.position.y = 0.8
		light.light_color = Color(1.0, 0.48, 0.18)
		light.light_energy = 0.8
		light.omni_range = 4.0
		light.shadow_enabled = false
		root.add_child(light)
		return root
	if kind == "bag":
		var mesh := MeshInstance3D.new()
		mesh.mesh = Meshes.get_mesh("bag")
		root.add_child(mesh)
		return root
	var model := CharacterModel.new()
	model.name = "Model"
	var height := 2.0
	if kind == "zombie":
		var look: Dictionary = ZOMBIE_LOOK[entity["type"]]
		model.setup(look["tint"], float(look["scale"]) * (
			1.75 if bool(entity.get("raid_boss", false)) else (
			1.18 if bool(entity.get("elite", false)) else 1.0)), look["walk"])
		height = 1.3 * float(look["scale"]) * (1.75 if bool(entity.get("raid_boss", false)) else 1.0)
	else:
		var hue := float(abs(int(entity["id"]) * 2654435761 % 1000)) / 1000.0
		model.setup(Color.from_hsv(hue, 0.45, 1.0), 2.0, 1.0)
	root.add_child(model)
	var label := Label3D.new()
	label.name = "Label"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.009
	label.font_size = 28
	label.outline_size = 8
	label.position = Vector3(0, height + 0.5, 0)
	root.add_child(label)
	return root


func _process(delta: float) -> void:
	var blend := 1.0 - exp(-14.0 * delta)
	for key in _nodes:
		var node: Node3D = _nodes[key]
		var target: Dictionary = _targets[key]
		node.position = node.position.lerp(target["position"], blend)
		if not (key.begins_with("bag") or key.begins_with("barricade") or key.begins_with("campfire")):
			node.rotation.y = lerp_angle(node.rotation.y, target["yaw"], blend)
			node.get_node("Model").update_motion(delta)
