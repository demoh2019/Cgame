extends Node3D
## Draws the moving things: other players, zombies and loot bags, smoothed between snapshots.

const Defs = preload("res://scripts/shared/defs.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const Meshes = preload("res://scripts/client/meshes.gd")
const CharacterModel = preload("res://scripts/client/character_model.gd")
const Assets = preload("res://scripts/client/assets.gd")
const LootLabel = preload("res://scripts/shared/loot_label.gd")

const ZOMBIE_LOOK := {
	"walker": {"tint": Color(0.62, 0.85, 0.55), "scale": 2.0, "walk": 0.8, "model": "Orc_Male"},
	"runner": {"tint": Color(0.9, 0.9, 0.45), "scale": 1.85, "walk": 1.8, "model": "Elf_Female"},
	"brute": {"tint": Color(0.55, 0.5, 0.7), "scale": 3.0, "walk": 0.7, "model": "Orc_Female"},
	"spitter": {"tint": Color(0.42, 0.87, 0.28), "scale": 2.1, "walk": 0.65, "model": "Orc_Male"},
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
	for id in client.spit_zones:
		_touch("spit:%d" % id, "spit_warning", client.spit_zones[id], seen)
	for id in client.acid_pools:
		_touch("pool:%d" % id, "acid_pool", client.acid_pools[id], seen)
	for id in client.bags:
		_touch("bag:%d" % id, "bag", client.bags[id], seen)
	for id in client.barricades:
		_touch("barricade:%d" % id, "barricade", client.barricades[id], seen)
	for id in client.campfires:
		_touch("campfire:%d" % id, "campfire", client.campfires[id], seen)
	for id in client.decoys:
		_touch("decoy:%d" % id, "decoy", client.decoys[id], seen)
	if not client.raid_telegraph.is_empty():
		_touch("raid_warning:%d" % int(client.raid_telegraph["id"]),
			"raid_warning", client.raid_telegraph, seen)
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
				"ENRAGED RAID BOSS " if bool(entity.get("raid_enraged", false)) else (
				"RAID BOSS " if bool(entity.get("raid_boss", false)) else (
				"ELITE " if bool(entity.get("elite", false)) else "")),
				str(entity["type"]), int(entity["hp"])]
		elif kind == "player":
			label.text = ("%s%s" % [
				"OUTLAW " if bool(entity.get("outlaw", false)) else "", str(entity["name"])]) if entity["alive"] else "%s (dead)" % entity["name"]
		elif kind == "bag":
			label.text = LootLabel.for_bag(entity)
			label.visible = not label.text.is_empty()
	if kind == "bag":
		# Gold = available to your party, grey = reserved, brown = public.
		var loot_mesh: MeshInstance3D = _nodes[key].get_child(0)
		var loot_material: StandardMaterial3D = loot_mesh.material_override
		if bool(entity.get("supply_drop", false)):
			loot_material.albedo_color = Color(0.20, 0.73, 0.96)
		elif bool(entity.get("reserved", false)):
			loot_material.albedo_color = (
				Color(0.96, 0.69, 0.22) if bool(entity.get("can_loot", false))
				else Color(0.43, 0.47, 0.51))
		else:
			loot_material.albedo_color = Color(0.64, 0.42, 0.23)
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
		if bool(entity.get("raid_enraged", false)):
			base = Color(1.0, 0.12, 0.12)
		elif bool(entity.get("raid_boss", false)):
			base = Color(0.92, 0.2, 0.63)
		elif bool(entity.get("elite", false)):
			base = Color(0.98, 0.65, 0.18)
		model.set_tint(base.lerp(ALERT_TINT, 0.45) if int(entity["state"]) >= 2 else base)
		model.set_zombie_state(int(entity["state"]))
	if kind == "player":
		var player_model: Node3D = _nodes[key].get_node("Model")
		if player_model.pack_mode:
			player_model.set_dead(not bool(entity["alive"])) # A dead player lies down instead of vanishing.
		else:
			player_model.visible = bool(entity["alive"])


func _make(kind: String, entity: Dictionary) -> Node3D:
	var root := Node3D.new()
	if kind == "acid_pool":
		var puddle := MeshInstance3D.new()
		var pool_disk := CylinderMesh.new()
		pool_disk.top_radius = float(entity.get("radius", 2.4))
		pool_disk.bottom_radius = pool_disk.top_radius
		pool_disk.height = 0.04
		puddle.mesh = pool_disk
		puddle.position.y = 0.07
		var poison := StandardMaterial3D.new()
		poison.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		poison.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		poison.albedo_color = Color(0.55, 0.45, 0.08, 0.55)
		puddle.material_override = poison
		root.add_child(puddle)
		return root
	if kind == "spit_warning":
		var warning := MeshInstance3D.new()
		var disk := CylinderMesh.new()
		disk.top_radius = float(entity.get("radius", 2.4))
		disk.bottom_radius = disk.top_radius
		disk.height = 0.06
		warning.mesh = disk
		warning.position.y = 0.08
		var chemical := StandardMaterial3D.new()
		chemical.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		chemical.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		chemical.albedo_color = Color(0.48, 1.0, 0.18, 0.38)
		warning.material_override = chemical
		root.add_child(warning)
		return root
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
	if kind == "decoy":
		var clacker := MeshInstance3D.new()
		var shape := CylinderMesh.new()
		shape.top_radius = 0.22
		shape.bottom_radius = 0.3
		shape.height = 0.26
		clacker.mesh = shape
		clacker.position.y = 0.18
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.98, 0.68, 0.16)
		clacker.material_override = material
		root.add_child(clacker)
		var label := Label3D.new()
		label.text = "NOISE LURE"
		label.name = "Label"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 18
		label.pixel_size = 0.006
		label.position.y = 1.0
		root.add_child(label)
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
	if kind == "raid_warning":
		# Flat translucent danger disc. No physics body, network authority or
		# client damage calculation; the server alone resolves the timed slam.
		var circle := MeshInstance3D.new()
		var shape := CylinderMesh.new()
		shape.top_radius = float(entity.get("radius", 5.0))
		shape.bottom_radius = shape.top_radius
		shape.height = 0.06
		shape.radial_segments = 48
		circle.mesh = shape
		circle.position.y = 0.16
		var warning_material := StandardMaterial3D.new()
		warning_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		warning_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		warning_material.albedo_color = Color(0.98, 0.12, 0.36, 0.30)
		warning_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		circle.material_override = warning_material
		root.add_child(circle)
		return root
	if kind == "bag":
		var mesh := MeshInstance3D.new()
		if Assets.has_village():
			mesh.mesh = Assets.village_mesh("EA03_Prop_Container_Basket_01a")
			mesh.scale = Vector3.ONE * 1.8
			var basket_material := mesh.mesh.surface_get_material(0)
			mesh.material_override = basket_material.duplicate() if basket_material is StandardMaterial3D else StandardMaterial3D.new()
		else:
			mesh.mesh = Meshes.get_mesh("bag")
			mesh.material_override = StandardMaterial3D.new()
		root.add_child(mesh)
		var label := Label3D.new()
		label.name = "Label"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.pixel_size = 0.008
		label.font_size = 24
		label.outline_size = 8
		label.position.y = 1.3
		label.visible = false
		root.add_child(label)
		return root
	var model := CharacterModel.new()
	model.name = "Model"
	var height := 2.0
	if kind == "zombie":
		var look: Dictionary = ZOMBIE_LOOK[entity["type"]]
		var zombie_model: String = look["model"]
		if entity["type"] == "walker" and int(entity["id"]) % 2 == 1:
			zombie_model = "Orc_Female"
		model.setup(look["tint"], float(look["scale"]) * (
			1.75 if bool(entity.get("raid_boss", false)) else (
			1.18 if bool(entity.get("elite", false)) else 1.0)), look["walk"], zombie_model, true)
		height = 1.3 * float(look["scale"]) * (1.75 if bool(entity.get("raid_boss", false)) else 1.0)
	else:
		var hue := float(abs(int(entity["id"]) * 2654435761 % 1000)) / 1000.0
		var character: String = Assets.CHARACTER_NAMES[int(abs(int(entity["id"]))) % Assets.CHARACTER_NAMES.size()]
		model.setup(Color.WHITE if Assets.has_characters() else Color.from_hsv(hue, 0.45, 1.0), 2.0, 1.0, character, false)
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


## A swing or a shot by another player.
func play_attack(peer_id: int, weapon_id: String, ranged: bool) -> void:
	var key := "player:%d" % peer_id
	if _nodes.has(key):
		_nodes[key].get_node("Model").play_action(attack_animation(weapon_id, ranged))


## Which animation a weapon uses.
static func attack_animation(weapon_id: String, ranged: bool) -> String:
	if ranged:
		return "Pistol_Shoot"
	if weapon_id == "":
		return "Punch_Jab"
	return "Sword_Regular_A"
