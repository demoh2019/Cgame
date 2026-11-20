extends Node3D
## Draws the moving things: other players, zombies and loot bags, smoothed between snapshots.

const Defs = preload("res://scripts/shared/defs.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const ModelCatalog = preload("res://scripts/client/model_catalog.gd")
const Meshes = preload("res://scripts/client/meshes.gd")
const CharacterModel = preload("res://scripts/client/character_model.gd")
const TrailBikeVisual = preload("res://scripts/client/trail_bike_visual.gd")
const HandFlareVisual = preload("res://scripts/client/hand_flare_visual.gd")
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


## The wall model of a tier, or a timber box when the packs are missing.
static func wall_mesh(tier: int) -> Mesh:
	var mesh: Mesh = ModelCatalog.barricade_mesh(tier)
	if mesh != null:
		return mesh
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 1.6, 0.5)
	var material := StandardMaterial3D.new()
	material.albedo_color = Structures.color_for_tier(tier)
	box.material = material
	return box


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
	for id in client.ember_pools:
		_touch("ember:%d" % id, "ember_pool", client.ember_pools[id], seen)
	for id in client.bags:
		_touch("bag:%d" % id, "bag", client.bags[id], seen)
	for id in client.barricades:
		_touch("barricade:%d" % id, "barricade", client.barricades[id], seen)
	for id in client.campfires:
		_touch("campfire:%d" % id, "campfire", client.campfires[id], seen)
	for id in client.shelters:
		_touch("shelter:%d" % id, "shelter", client.shelters[id], seen)
	for id in client.decoys:
		_touch("decoy:%d" % id, "decoy", client.decoys[id], seen)
	for id in client.smoke_clouds:
		_touch("smoke:%d" % id, "smoke", client.smoke_clouds[id], seen)
	for id in client.infected_snares:
		_touch("snare:%d" % id, "snare", client.infected_snares[id], seen)
	for id in client.fish_traps:
		_touch("fish_trap:%d" % id, "fish_trap", client.fish_traps[id], seen)
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
		if kind == "fish_trap":
			label.text = "FISH NET T%d | %s" % [
				int(entity.get("tier", 1)), "READY" if bool(entity.get("ready", false)) else
				("%ds" % ceili(float(entity.get("ready_in", 0.0))))]
		elif kind == "zombie":
			label.visible = false # The overlay draws a health bar instead (world_overlay.gd).
			label.text = "%s%s  %d" % [
				"ENRAGED RAID BOSS " if bool(entity.get("raid_enraged", false)) else (
				"RAID BOSS " if bool(entity.get("raid_boss", false)) else (
				"ELITE " if bool(entity.get("elite", false)) else "")),
				str(entity["type"]), int(entity["hp"])]
			if float(entity.get("stagger_seconds", 0.0)) > 0.0:
				label.text += " [STAGGERED]"
			elif float(entity.get("snared_seconds", 0.0)) > 0.0:
				label.text += " [PINNED]"
			if float(entity.get("sunder_seconds", 0.0)) > 0.0:
				label.text += " [EXPOSED]"
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
			loot_material.albedo_color = (Color(0.91, 0.33, 0.16)
				if int(entity.get("guards_remaining", 0)) > 0 else Color(0.20, 0.73, 0.96))
		elif bool(entity.get("reserved", false)):
			loot_material.albedo_color = (
				Color(0.96, 0.69, 0.22) if bool(entity.get("can_loot", false))
				else Color(0.43, 0.47, 0.51))
		else:
			loot_material.albedo_color = Color(0.64, 0.42, 0.23)
	if kind == "barricade":
		# The tier's wall model, turned to its facing, darkening as it is damaged.
		var barricade_mesh: MeshInstance3D = _nodes[key].get_node("Wall")
		var tier: int = Structures.tier_of(entity)
		if int(barricade_mesh.get_meta("tier", 0)) != tier:
			barricade_mesh.set_meta("tier", tier)
			barricade_mesh.mesh = wall_mesh(tier)
			if barricade_mesh.material_overlay == null:
				var wear := StandardMaterial3D.new()
				wear.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				wear.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				barricade_mesh.material_overlay = wear
		_nodes[key].rotation.y = float(entity.get("yaw", 0.0))
		var fraction: float = clampf(float(entity.get("hp", 0.0)) / maxf(1.0, Structures.max_health(tier)), 0.0, 1.0)
		(barricade_mesh.material_overlay as StandardMaterial3D).albedo_color = Color(0.08, 0.06, 0.05, (1.0 - fraction) * 0.6)
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
		var staggered: bool = float(entity.get("stagger_seconds", 0.0)) > 0.0
		var pinned: bool = float(entity.get("snared_seconds", 0.0)) > 0.0
		var exposed: bool = float(entity.get("sunder_seconds", 0.0)) > 0.0
		var tint: Color = base.lerp(ALERT_TINT, 0.45) if int(entity["state"]) >= 2 else base
		if exposed:
			tint = base.lerp(Color(0.96, 0.42, 0.14), 0.65)
		if pinned:
			tint = base.lerp(Color(1.0, 0.84, 0.25), 0.65)
		if staggered:
			tint = base.lerp(Color(0.38, 0.8, 1.0), 0.7)
		model.set_tint(tint)
		model.set_zombie_state(int(entity["state"]))
	if kind == "player":
		_nodes[key].get_node("HandFlare").set_burning(bool(entity.get("flare_lit", false)) and bool(entity.get("alive", false)))
		var bike = _nodes[key].get_node("TrailBike")
		bike.set_panniers(bool(entity.get("bike_panniers", false)))
		bike.set_lamp(bool(entity.get("bike_lamp_lit", false)))
		bike.set_riding(bool(entity.get("mounted", false)) and bool(entity.get("alive", false)))
		var player_model: Node3D = _nodes[key].get_node("Model")
		if player_model.pack_mode:
			# Sneaking and riding are real poses; the weapon they carry is in their hand.
			player_model.set_stance(bool(entity.get("crouching", false)), bool(entity.get("mounted", false)))
			player_model.set_weapon(str(entity.get("weapon", "")))
			player_model.set_gear(entity.get("gear", {}) if entity.get("gear", {}) is Dictionary else {})
		else:
			player_model.scale = Vector3(1.0, 0.72 if bool(entity.get("crouching", false)) else 1.0, 1.0)
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
	if kind == "ember_pool":
		var embers := MeshInstance3D.new()
		var shape := CylinderMesh.new()
		shape.top_radius = float(entity.get("radius", 3.0))
		shape.bottom_radius = shape.top_radius
		shape.height = 0.06
		embers.mesh = shape
		embers.position.y = 0.10
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.36, 0.07, 0.43)
		embers.material_override = mat
		root.add_child(embers)
		var light := OmniLight3D.new()
		light.position.y = 0.8
		light.light_color = Color(1.0, 0.32, 0.08)
		light.light_energy = 0.55
		light.omni_range = 4.5
		light.shadow_enabled = false
		root.add_child(light)
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
		barricade.name = "Wall"
		root.add_child(barricade)
		return root
	if kind == "fish_trap":
		var bobber := MeshInstance3D.new()
		var shape := CylinderMesh.new()
		shape.top_radius = 0.42
		shape.bottom_radius = 0.45
		shape.height = 0.22
		bobber.mesh = shape
		bobber.position.y = 0.12
		var orange := StandardMaterial3D.new()
		orange.albedo_color = Color(0.83, 0.49, 0.15)
		bobber.material_override = orange
		root.add_child(bobber)
		var net := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.12, 0.07, 1.12)
		net.mesh = mesh
		net.position.y = 0.015
		var gray := StandardMaterial3D.new()
		gray.albedo_color = Color(0.30, 0.36, 0.25)
		net.material_override = gray
		root.add_child(net)
		var label := Label3D.new()
		label.name = "Label"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 18
		label.pixel_size = 0.007
		label.position.y = 1.0
		root.add_child(label)
		return root
	if kind == "snare":
		var tripwire := MeshInstance3D.new()
		var bar := BoxMesh.new()
		bar.size = Vector3(1.8, 0.12, 0.22)
		tripwire.mesh = bar
		tripwire.position.y = 0.08
		var metal := StandardMaterial3D.new()
		metal.albedo_color = Color(0.78, 0.53, 0.22)
		tripwire.material_override = metal
		root.add_child(tripwire)
		var label := Label3D.new()
		label.name = "Label"
		label.text = "SNARE"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 18
		label.pixel_size = 0.006
		label.position.y = 0.7
		root.add_child(label)
		return root
	if kind == "smoke":
		var cloud := MeshInstance3D.new()
		var shape := SphereMesh.new()
		shape.radius = float(entity.get("radius", 4.5))
		shape.height = 3.2
		shape.radial_segments = 24
		shape.rings = 12
		cloud.mesh = shape
		cloud.position.y = 1.6
		var haze := StandardMaterial3D.new()
		haze.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		haze.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		haze.albedo_color = Color(0.52, 0.57, 0.58, 0.28)
		haze.cull_mode = BaseMaterial3D.CULL_DISABLED
		cloud.material_override = haze
		root.add_child(cloud)
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
	if kind == "shelter":
		var canopy := MeshInstance3D.new()
		var roof := BoxMesh.new()
		roof.size = Vector3(3.0, 0.12, 2.6)
		canopy.mesh = roof
		canopy.position.y = 1.8
		var canvas := StandardMaterial3D.new()
		canvas.albedo_color = Color(0.31, 0.42, 0.29)
		canopy.material_override = canvas
		root.add_child(canopy)
		for dx in [-1.25, 1.25]:
			for dz in [-1.08, 1.08]:
				var pole := MeshInstance3D.new()
				var pole_mesh := CylinderMesh.new()
				pole_mesh.top_radius = 0.045
				pole_mesh.bottom_radius = 0.06
				pole_mesh.height = 1.75
				pole.mesh = pole_mesh
				pole.position = Vector3(dx, 0.89, dz)
				var wood := StandardMaterial3D.new()
				wood.albedo_color = Color(0.35, 0.24, 0.16)
				pole.material_override = wood
				root.add_child(pole)
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
			1.18 if bool(entity.get("elite", false)) else 1.0)), look["walk"], zombie_model, true, int(entity["id"]))
		height = 1.3 * float(look["scale"]) * (1.75 if bool(entity.get("raid_boss", false)) else 1.0)
	else:
		var hue := float(abs(int(entity["id"]) * 2654435761 % 1000)) / 1000.0
		var character: String = Assets.CHARACTER_NAMES[int(abs(int(entity["id"]))) % Assets.CHARACTER_NAMES.size()]
		model.setup(Color.WHITE if Assets.has_characters() else Color.from_hsv(hue, 0.45, 1.0), 2.0, 1.0, character, false, int(abs(int(entity["id"]))) / Assets.CHARACTER_NAMES.size())
	root.add_child(model)
	if kind == "player":
		var bike := TrailBikeVisual.new()
		bike.name = "TrailBike"
		root.add_child(bike)
		var flare := HandFlareVisual.new()
		flare.name = "HandFlare"
		root.add_child(flare)
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
		if not (key.begins_with("bag") or key.begins_with("barricade") or key.begins_with("campfire") or key.begins_with("shelter") or key.begins_with("smoke") or key.begins_with("snare") or key.begins_with("fish_trap") or key.begins_with("decoy") or key.begins_with("pool") or key.begins_with("ember") or key.begins_with("spit")):
			node.rotation.y = lerp_angle(node.rotation.y, target["yaw"], blend)
			var model: Node3D = node.get_node("Model")
			model.update_motion(delta)
			if key.begins_with("player:"):
				var bike = node.get_node("TrailBike")
				if bike.visible:
					bike.set_riding(true, model.speed, delta)


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
		return "Punch_Jab" if randf() < 0.55 else "Punch_Cross"
	match CharacterModel.weapon_family(weapon_id):
		"sledgehammer", "purifier_maul", "sunder_axe":
			return "Sword_Regular_C" # Big overhead blows.
		"spear":
			return "Sword_Regular_B"
		"restoration_staff":
			return "Spell_Simple_Shoot"
	return "Sword_Regular_A" if randf() < 0.5 else "Sword_Regular_B"


## Any one-shot animation on a player or zombie drawn here.
func play_action_on(kind: String, id: int, animation_name: String) -> void:
	var key := "%s:%d" % [kind, id]
	if _nodes.has(key) and _nodes[key].has_node("Model"):
		_nodes[key].get_node("Model").play_action(animation_name, 1.2)


## A flinch on whoever was struck.
func play_hit(kind: String, id: int, heavy: bool = false) -> void:
	var key := "%s:%d" % [kind, id]
	if _nodes.has(key) and _nodes[key].has_node("Model"):
		var model = _nodes[key].get_node("Model")
		if model.has_method("play_hit"):
			model.play_hit(heavy)
