extends Node3D
## Draws the moving things: other players, zombies and loot bags, smoothed between snapshots.

const Defs = preload("res://scripts/shared/defs.gd")
const Meshes = preload("res://scripts/client/meshes.gd")

const ZOMBIE_LOOK := {
	"walker": {"color": Color(0.45, 0.55, 0.42), "scale": Vector3(1.0, 1.0, 1.0)},
	"runner": {"color": Color(0.62, 0.62, 0.3), "scale": Vector3(0.85, 1.05, 0.85)},
	"brute": {"color": Color(0.35, 0.32, 0.4), "scale": Vector3(1.55, 1.4, 1.55)},
}

var _nodes: Dictionary = {} # "kind:id" -> Node3D
var _targets: Dictionary = {} # "kind:id" -> {"position": Vector3, "yaw": float}


func update_from(client) -> void:
	var seen: Dictionary = {}
	for id in client.players:
		var e: Dictionary = client.players[id]
		_touch("player:%d" % id, "player", e, seen, client)
	for id in client.zombies:
		var e: Dictionary = client.zombies[id]
		_touch("zombie:%d" % id, "zombie", e, seen, client)
	for id in client.bags:
		var e: Dictionary = client.bags[id]
		_touch("bag:%d" % id, "bag", e, seen, client)
	for key in _nodes.keys():
		if not seen.has(key):
			_nodes[key].queue_free()
			_nodes.erase(key)
			_targets.erase(key)


func _touch(key: String, kind: String, entity: Dictionary, seen: Dictionary, _client) -> void:
	seen[key] = true
	if not _nodes.has(key):
		_nodes[key] = _make(kind, entity)
		add_child(_nodes[key])
		_nodes[key].position = Vector3(entity["x"], entity["y"], entity["z"])
	_targets[key] = {"position": Vector3(entity["x"], entity["y"], entity["z"]), "yaw": float(entity.get("yaw", 0.0))}
	var label: Label3D = _nodes[key].get_node_or_null("Label")
	if label != null:
		if kind == "zombie":
			label.text = "%s  %d" % [entity["type"], int(entity["hp"])]
		elif kind == "player":
			label.text = str(entity["name"]) if entity["alive"] else "%s (dead)" % entity["name"]
	if kind == "zombie":
		var body: MeshInstance3D = _nodes[key].get_node("Body")
		var material: StandardMaterial3D = body.material_override
		# A zombie that has locked on to someone flushes red.
		material.albedo_color = ZOMBIE_LOOK[entity["type"]]["color"].lerp(Color(0.9, 0.2, 0.15), 0.55 if int(entity["state"]) >= 2 else 0.0)


func _make(kind: String, entity: Dictionary) -> Node3D:
	var root := Node3D.new()
	if kind == "bag":
		var mesh := MeshInstance3D.new()
		mesh.mesh = Meshes.get_mesh("bag")
		root.add_child(mesh)
		return root
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = Meshes.get_mesh("body")
	var material := StandardMaterial3D.new()
	material.roughness = 0.9
	material.vertex_color_use_as_albedo = true
	if kind == "zombie":
		var look: Dictionary = ZOMBIE_LOOK[entity["type"]]
		material.albedo_color = look["color"]
		body.scale = look["scale"]
	else:
		var hue := float(abs(int(entity["id"]) * 2654435761 % 1000)) / 1000.0
		material.albedo_color = Color.from_hsv(hue, 0.55, 0.85)
	body.material_override = material
	root.add_child(body)
	var label := Label3D.new()
	label.name = "Label"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.009
	label.font_size = 28
	label.outline_size = 8
	label.position = Vector3(0, 2.5 if kind == "player" else 2.4 * body.scale.y, 0)
	root.add_child(label)
	return root


func _process(delta: float) -> void:
	var blend := 1.0 - exp(-14.0 * delta)
	for key in _nodes:
		var node: Node3D = _nodes[key]
		var target: Dictionary = _targets[key]
		node.position = node.position.lerp(target["position"], blend)
		if not key.begins_with("bag"):
			node.rotation.y = lerp_angle(node.rotation.y, target["yaw"], blend)
