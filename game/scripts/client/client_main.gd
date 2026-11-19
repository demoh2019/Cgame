extends Node3D
## Local playable client of the SAME authoritative simulation used by the dedicated server.
## Not a second set of gameplay rules: gathering, combat, loot, survival and crafting all
## call GameServer. Multiplayer transport will be wired to this presentation separately.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const LOCAL_PLAYER_ID := 2
const TERRAIN_STEP := 8.0
const RECIPES := ["plank_1", "cloth_1", "bar_1", "axe_1", "pickaxe_1", "club_1", "jacket_1", "bandage"]

var world
var sim
var survivor
var _sequence: int = 0
var _facing: Vector2 = Vector2(0.0, -1.0)
var _recipe_index: int = 0
var _camera: Camera3D
var _avatar: MeshInstance3D
var _stats: Label
var _instructions: Label
var _feedback: String = "Leave the safe hub to gather. Return to the workbench to craft."
var _chunks: Dictionary = {}
var _resource_meshes: Dictionary = {}
var _crate_meshes: Dictionary = {}
var _zombie_meshes: Dictionary = {}
var _barricade_bodies: Dictionary = {}
var _materials: Dictionary = {}
var _last_center: Vector2i = Vector2i(999999, 999999)
var _hud_clock: float = 0.0


func _ready() -> void:
	_setup_actions()
	world = WorldGen.new(1337)
	sim = GameServer.new(world, 1337)
	survivor = sim.add_player(LOCAL_PLAYER_ID, "Survivor")
	_make_light_and_camera()
	_make_avatar()
	_make_workbench()
	_make_hud()
	_stream_chunks()
	_update_hud()


func _setup_actions() -> void:
	_bind_key("survive_up", KEY_W)
	_bind_key("survive_down", KEY_S)
	_bind_key("survive_left", KEY_A)
	_bind_key("survive_right", KEY_D)
	_bind_key("survive_sprint", KEY_SHIFT)
	_bind_key("survive_gather", KEY_E)
	_bind_key("survive_loot", KEY_Q)
	_bind_key("survive_attack", KEY_F)
	_bind_key("survive_craft", KEY_C)
	_bind_key("survive_next_recipe", KEY_TAB)
	_bind_key("survive_food", KEY_1)
	_bind_key("survive_water", KEY_2)
	_bind_key("survive_bandage", KEY_3)
	_bind_key("survive_weapon", KEY_4)
	_bind_key("survive_armor", KEY_5)
	_bind_key("survive_lake", KEY_R)
	_bind_key("survive_build", KEY_B)
	_bind_key("survive_repair", KEY_H)


func _bind_key(action: StringName, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)


func _make_light_and_camera() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.19, 0.24)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.73)
	env.ambient_light_energy = 0.7
	env_node.environment = env
	add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	sun.light_energy = 1.3
	add_child(sun)
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.current = true
	_camera.fov = 58.0
	add_child(_camera)


func _mesh(box_size: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	instance.mesh = box
	var key := str(color)
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.96
		_materials[key] = material
	instance.material_override = _materials[key]
	return instance


func _make_avatar() -> void:
	_avatar = _mesh(Vector3(0.8, 1.7, 0.8), Color(0.25, 0.69, 0.84))
	_avatar.name = "Survivor"
	add_child(_avatar)


## A visible landmark for the station validation enforced by GameServer.
func _make_workbench() -> void:
	var bench := _mesh(Vector3(2.8, 1.0, 1.6), Color(0.88, 0.68, 0.26))
	bench.name = "Workbench"
	bench.position = Vector3(
			GameServer.WORKBENCH_POSITION.x,
			world.height_at(GameServer.WORKBENCH_POSITION.x, GameServer.WORKBENCH_POSITION.y) + 0.5,
			GameServer.WORKBENCH_POSITION.y)
	add_child(bench)


func _make_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	_stats = Label.new()
	_stats.name = "Stats"
	_stats.position = Vector2(18, 18)
	_stats.add_theme_font_size_override("font_size", 17)
	layer.add_child(_stats)
	_instructions = Label.new()
	_instructions.name = "Instructions"
	_instructions.position = Vector2(18, 145)
	_instructions.add_theme_font_size_override("font_size", 15)
	layer.add_child(_instructions)


func _terrain_color(x: float, z: float) -> Color:
	if world.is_safe(x, z):
		return Color(0.32, 0.41, 0.31)
	match world.biome_at(x, z):
		"water":
			return Color(0.12, 0.3, 0.52)
		"beach":
			return Color(0.53, 0.51, 0.36)
		"mountain":
			return Color(0.42, 0.42, 0.44)
		"swamp":
			return Color(0.29, 0.38, 0.26)
		"forest":
			return Color(0.28, 0.43, 0.27)
		_:
			return Color(0.43, 0.41, 0.31)


func _terrain_vertex(surface: SurfaceTool, x: float, z: float) -> void:
	surface.set_color(_terrain_color(x, z))
	surface.add_vertex(Vector3(x, world.height_at(x, z) - 0.12, z))


func _make_terrain(cell: Vector2i) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var origin: Vector2 = WorldGen.cell_origin(cell)
	var steps: int = int(Defs.CHUNK_SIZE / TERRAIN_STEP)
	for ix in range(steps):
		for iz in range(steps):
			var x: float = origin.x + float(ix) * TERRAIN_STEP
			var z: float = origin.y + float(iz) * TERRAIN_STEP
			_terrain_vertex(surface, x, z)
			_terrain_vertex(surface, x, z + TERRAIN_STEP)
			_terrain_vertex(surface, x + TERRAIN_STEP, z)
			_terrain_vertex(surface, x + TERRAIN_STEP, z)
			_terrain_vertex(surface, x, z + TERRAIN_STEP)
			_terrain_vertex(surface, x + TERRAIN_STEP, z + TERRAIN_STEP)
	surface.generate_normals()
	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	terrain.material_override = material
	return terrain


func _make_chunk(cell: Vector2i) -> Node3D:
	var chunk_node := Node3D.new()
	chunk_node.name = "Chunk_%d_%d" % [cell.x, cell.y]
	chunk_node.add_child(_make_terrain(cell))
	var chunk_data: Dictionary = world.chunk(cell)
	for node in chunk_data["nodes"]:
		var tint := Color(0.29, 0.62, 0.35)
		match str(node["kind"]):
			"rock", "ore":
				tint = Color(0.58, 0.6, 0.62)
			"bush", "berry":
				tint = Color(0.68, 0.72, 0.3)
		var visible_node := _mesh(Vector3(1.0, 1.25, 1.0), tint)
		visible_node.position = Vector3(node["x"], node["y"] + 0.55, node["z"])
		chunk_node.add_child(visible_node)
		_resource_meshes[int(node["id"])] = visible_node
	for crate in chunk_data["crates"]:
		var visible_crate := _mesh(Vector3(1.1, 0.7, 1.0), Color(0.67, 0.42, 0.21))
		visible_crate.position = Vector3(crate["x"], crate["y"] + 0.35, crate["z"])
		chunk_node.add_child(visible_crate)
		_crate_meshes[int(crate["id"])] = visible_crate
	return chunk_node


func _stream_chunks() -> void:
	var center: Vector2i = WorldGen.cell_of(survivor.position.x, survivor.position.z)
	if center == _last_center:
		return
	_last_center = center
	for cell in _chunks.keys():
		if abs(cell.x - center.x) > 1 or abs(cell.y - center.y) > 1:
			var old_chunk: Node3D = _chunks[cell]
			for item_id in _resource_meshes.keys():
				if old_chunk.is_ancestor_of(_resource_meshes[item_id]):
					_resource_meshes.erase(item_id)
			for item_id in _crate_meshes.keys():
				if old_chunk.is_ancestor_of(_crate_meshes[item_id]):
					_crate_meshes.erase(item_id)
			_chunks.erase(cell)
			old_chunk.queue_free()
	for cx in range(center.x - 1, center.x + 2):
		for cz in range(center.y - 1, center.y + 2):
			var cell := Vector2i(cx, cz)
			if not _chunks.has(cell):
				var chunk: Node3D = _make_chunk(cell)
				add_child(chunk)
				_chunks[cell] = chunk


func _sync_zombies() -> void:
	var active: Dictionary = {}
	for zombie in sim.zombies.values():
		if not zombie.is_alive() or zombie.position.distance_to(survivor.position) > 72.0:
			continue
		active[zombie.id] = true
		if not _zombie_meshes.has(zombie.id):
			var mesh := _mesh(Vector3(0.85, 1.6, 0.85), Color(0.66, 0.37, 0.35))
			add_child(mesh)
			_zombie_meshes[zombie.id] = mesh
		_zombie_meshes[zombie.id].position = zombie.position + Vector3(0.0, 0.8, 0.0)
	for zombie_id in _zombie_meshes.keys():
		if not active.has(zombie_id):
			_zombie_meshes[zombie_id].queue_free()
			_zombie_meshes.erase(zombie_id)


func _sync_barricades() -> void:
	var active: Dictionary = {}
	for id in sim.barricades:
		var wall: Dictionary = sim.barricades[id]
		var point := Vector3(float(wall["x"]), float(wall["y"]) + 0.8, float(wall["z"]))
		if survivor.position.distance_to(point) > 95.0:
			continue
		active[id] = true
		if not _barricade_bodies.has(id):
			var body := StaticBody3D.new()
			body.name = "Barricade_%d" % int(id)
			var shape_node := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(1.7, 1.6, 1.7)
			shape_node.shape = box
			body.add_child(shape_node)
			var visual := _mesh(box.size, Color(0.57, 0.40, 0.23))
			visual.name = "Body"
			body.add_child(visual)
			add_child(body)
			_barricade_bodies[id] = body
		var structure: StaticBody3D = _barricade_bodies[id]
		structure.position = point
		var visual: MeshInstance3D = structure.get_node("Body")
		var health_fraction := clampf(float(wall["hp"]) / 120.0, 0.0, 1.0)
		var material: StandardMaterial3D = visual.material_override
		if material == null or material == _materials.get(str(Color(0.57, 0.40, 0.23))):
			material = StandardMaterial3D.new()
			visual.material_override = material
		material.albedo_color = Color(0.27, 0.20, 0.17).lerp(Color(0.64, 0.48, 0.3), health_fraction)
	for id in _barricade_bodies.keys():
		if not active.has(id):
			_barricade_bodies[id].queue_free()
			_barricade_bodies.erase(id)


func _nearest_barricade() -> int:
	var nearest := -1
	var distance := 3.0
	var current := Vector2(survivor.position.x, survivor.position.z)
	for id in sim.barricades:
		var item: Dictionary = sim.barricades[id]
		var delta_position := Vector2(float(item["x"]), float(item["z"])) - current
		var d := delta_position.length()
		if d < distance and (d < 0.001 or delta_position.normalized().dot(_facing) > 0.15):
			distance = d
			nearest = int(id)
	return nearest


func _physics_process(delta: float) -> void:
	if sim == null:
		return
	sim.tick(delta)
	var movement := Input.get_vector("survive_left", "survive_right", "survive_up", "survive_down")
	if movement.length_squared() > 0.001:
		_facing = movement.normalized()
	_sequence += 1
	sim.submit_input(LOCAL_PLAYER_ID, _sequence, movement.x, movement.y,
			Input.is_action_pressed("survive_sprint"), atan2(_facing.x, _facing.y), delta)
	_avatar.position = survivor.position + Vector3(0, 0.85, 0)
	_camera.position = _camera.position.lerp(survivor.position + Vector3(0, 22, 27), minf(1.0, delta * 7.0))
	_camera.look_at(survivor.position + Vector3(0, 0.7, 0), Vector3.UP)
	_stream_chunks()
	for item_id in _resource_meshes:
		_resource_meshes[item_id].visible = not sim.depleted.has(item_id)
	for item_id in _crate_meshes:
		_crate_meshes[item_id].visible = not sim.opened_crates.has(item_id)
	_sync_zombies()
	_sync_barricades()
	_hud_clock += delta
	if _hud_clock > 0.15:
		_hud_clock = 0.0
		_update_hud()


func _nearest_node() -> Dictionary:
	var found: Dictionary = {}
	var distance: float = Defs.REACH + 0.5
	var cell: Vector2i = WorldGen.cell_of(survivor.position.x, survivor.position.z)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for node in world.chunk(Vector2i(cell.x + dx, cell.y + dz))["nodes"]:
				if sim.depleted.has(node["id"]):
					continue
				var d := Vector2(survivor.position.x - float(node["x"]), survivor.position.z - float(node["z"])).length()
				if d < distance:
					found = node
					distance = d
	return found


func _nearest_loot() -> Dictionary:
	var found: Dictionary = {}
	var distance: float = Defs.REACH + 0.5
	for bag in sim.bags.values():
		var d := Vector2(survivor.position.x - float(bag["x"]), survivor.position.z - float(bag["z"])).length()
		if d < distance:
			found = bag
			distance = d
	var cell: Vector2i = WorldGen.cell_of(survivor.position.x, survivor.position.z)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for crate in world.chunk(Vector2i(cell.x + dx, cell.y + dz))["crates"]:
				if sim.opened_crates.has(crate["id"]):
					continue
				var d := Vector2(survivor.position.x - float(crate["x"]), survivor.position.z - float(crate["z"])).length()
				if d < distance:
					found = crate
					distance = d
	return found


func _result(action: String, data: Dictionary) -> void:
	if bool(data.get("ok", false)):
		_feedback = "%s: SUCCESS" % action
	else:
		_feedback = "%s: %s" % [action, str(data.get("reason", "failed"))]
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("survive_gather"):
		var target := _nearest_node()
		if target.is_empty():
			_feedback = "No resource within reach."
		else:
			_result("Gather", sim.cmd_gather(LOCAL_PLAYER_ID, target["id"]))
	elif event.is_action_pressed("survive_loot"):
		var target := _nearest_loot()
		if target.is_empty():
			_feedback = "No nearby crate or loot bag."
		else:
			_result("Loot", sim.cmd_loot(LOCAL_PLAYER_ID, target["id"]))
	elif event.is_action_pressed("survive_attack"):
		_result("Attack", sim.cmd_attack(LOCAL_PLAYER_ID, _facing.x, _facing.y))
	elif event.is_action_pressed("survive_next_recipe"):
		_recipe_index = (_recipe_index + 1) % RECIPES.size()
	elif event.is_action_pressed("survive_craft"):
		_result("Craft", sim.cmd_craft(LOCAL_PLAYER_ID, RECIPES[_recipe_index]))
	elif event.is_action_pressed("survive_food"):
		_result("Eat", sim.cmd_use(LOCAL_PLAYER_ID, "canned_food"))
	elif event.is_action_pressed("survive_water"):
		_result("Drink", sim.cmd_use(LOCAL_PLAYER_ID, "water_bottle"))
	elif event.is_action_pressed("survive_bandage"):
		_result("Heal", sim.cmd_use(LOCAL_PLAYER_ID, "bandage"))
	elif event.is_action_pressed("survive_weapon"):
		_result("Equip weapon", sim.cmd_use(LOCAL_PLAYER_ID, "club_1"))
	elif event.is_action_pressed("survive_armor"):
		_result("Equip armor", sim.cmd_use(LOCAL_PLAYER_ID, "jacket_1"))
	elif event.is_action_pressed("survive_lake"):
		_result("Drink from water", sim.cmd_drink_water(LOCAL_PLAYER_ID))
	elif event.is_action_pressed("survive_build"):
		var point := Vector2(survivor.position.x, survivor.position.z) + _facing * 2.8
		_result("Build barricade", sim.cmd_build(LOCAL_PLAYER_ID, point.x, point.y))
	elif event.is_action_pressed("survive_repair"):
		var wall_id := _nearest_barricade()
		if wall_id == -1:
			_feedback = "Repair: aim toward a nearby barricade"
		else:
			_result("Repair barricade", sim.cmd_repair(LOCAL_PLAYER_ID, wall_id))


func _update_hud() -> void:
	if survivor == null:
		return
	var vitals = survivor.survival
	var position: Vector3 = survivor.position
	var zone: int = world.zone_at(position.x, position.z)
	var rows: PackedStringArray = []
	for slot in survivor.inventory.slots:
		if not slot.is_empty():
			rows.append("%s:%d" % [str(slot["id"]), int(slot["count"])])
	_stats.text = "ALBION AFTER | LOCAL SURVIVAL PREVIEW\nHP %d  HUNGER %d  THIRST %d  KILLS %d\nZONE %s (T%d)  POS %d,%d  ZOMBIES %d\nINVENTORY %s" % [
		int(vitals.health), int(vitals.hunger), int(vitals.thirst), survivor.kills,
		Defs.ZONE_NAMES[zone], WorldGen.tier_for_zone(zone), int(position.x), int(position.z),
		sim.zombies.size(), ", ".join(rows)
	]
	var recipe: Dictionary = Defs.recipes()[RECIPES[_recipe_index]]
	var near_bench: bool = Vector2(position.x, position.z).distance_to(GameServer.WORKBENCH_POSITION) < GameServer.WORKBENCH_RANGE
	_instructions.text = "WASD move | Shift sprint | E gather | Q loot | F attack | B build | H repair (%d walls)\nTab recipe | C craft | 1 eat 2 drink 3 bandage 4 weapon 5 armor R lake\nCRAFT %s -> %s x%d | %s | inputs %s\n%s" % [
		sim.barricades.size(), RECIPES[_recipe_index], str(recipe["output"]), int(recipe["count"]),
		"WORKBENCH" if near_bench else "workbench at x=9, z=0",
		str(recipe["inputs"]), _feedback
	]
