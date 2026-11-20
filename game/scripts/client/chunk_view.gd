extends Node3D
## The visual side of one world chunk: its terrain and every tree, rock, bush and crate in it.
## Nothing here is sent over the network. It is built from the seed, and only the "depleted" and
## "opened" flags from the server change what is shown.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Meshes = preload("res://scripts/client/meshes.gd")
const Assets = preload("res://scripts/client/assets.gd")
const Foliage = preload("res://scripts/client/foliage.gd")
const CharacterModel = preload("res://scripts/client/character_model.gd")
const ModelCatalog = preload("res://scripts/client/model_catalog.gd")

const SAMPLES := 33 # Heights per side: one every 2 m.
const HEIGHT_MIN := -45.0
const HEIGHT_RANGE := 220.0
const GROUND_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// A painted-looking ground: smooth patches of lush and dry grass, dirt, sand at the shore, strata on slopes and
// snow on the peaks, all from layered value noise so nothing repeats in a visible grid.
varying vec3 world_position;
varying vec3 world_normal;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p = p * 2.03 + 17.0;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world_position.xz;
	float h = world_position.y;
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float broad = fbm(p * 0.012);
	float mid = fbm(p * 0.09 + 3.0);
	float fine = value_noise(p * 3.1);
	float speck = value_noise(p * 11.0);

	vec3 lush = vec3(0.14, 0.34, 0.1);
	vec3 dry = vec3(0.4, 0.42, 0.18);
	vec3 meadow = mix(lush, dry, smoothstep(0.35, 0.7, broad));
	meadow *= 0.78 + 0.5 * mid;
	meadow = mix(meadow, meadow * vec3(1.15, 1.1, 0.75), smoothstep(0.65, 0.9, speck) * 0.5);
	meadow *= 0.93 + 0.14 * fine;
	vec3 dirt = vec3(0.34, 0.25, 0.16) * (0.8 + 0.4 * mid);
	vec3 sand = vec3(0.62, 0.55, 0.38) * (0.92 + 0.12 * fine);
	vec3 rock = vec3(0.45, 0.42, 0.4);
	float strata = fbm(vec2(p.x * 0.18 + p.y * 0.14, h * 1.6));
	rock *= 0.65 + 0.7 * strata;
	vec3 snow = vec3(0.94, 0.96, 1.0);

	vec3 color = meadow;
	// Bare earth in patches and along steeper ground.
	color = mix(color, dirt, smoothstep(0.62, 0.8, mid + slope * 0.9) * 0.85);
	// Sand and wet ground at the shore.
	float shore = 1.0 - smoothstep(0.4, 2.4, h + (broad - 0.5) * 1.2);
	color = mix(color, sand, shore);
	color = mix(color, color * 0.55, 1.0 - smoothstep(-1.4, 0.7, h));
	// Cliffs and mountains.
	color = mix(color, rock, smoothstep(0.2, 0.46, slope + (strata - 0.5) * 0.12));
	color = mix(color, rock * 0.85, smoothstep(40.0, 58.0, h));
	color = mix(color, snow, smoothstep(88.0, 108.0, h + (broad - 0.5) * 14.0) * (1.0 - smoothstep(0.3, 0.55, slope)));

	ALBEDO = color;
	ROUGHNESS = mix(0.95, 0.75, shore);
	SPECULAR = 0.15;
}
"""

static var _ground_material: ShaderMaterial

var cell: Vector2i
var _world
var _terrain
var _groups: Dictionary = {} # kind -> {"multimesh": MultiMesh, "index": {node_id: i}, "transforms": [...]}
var _hidden: Dictionary = {} # node id -> true, currently hidden
var _use_nature := false
var _use_village := false


static func ground_material() -> ShaderMaterial:
	if _ground_material == null:
		var shader := Shader.new()
		shader.code = GROUND_SHADER
		_ground_material = ShaderMaterial.new()
		_ground_material.shader = shader
	return _ground_material


func build(p_world, p_cell: Vector2i) -> void:
	_use_nature = Assets.has_nature()
	_use_village = Assets.has_village()
	_world = p_world
	cell = p_cell
	var origin := WorldGen.cell_origin(cell)
	_build_terrain(origin)
	var data: Dictionary = _world.chunk(cell)
	_build_objects(data)


func _build_terrain(origin: Vector2) -> void:
	var heights := PackedFloat32Array()
	heights.resize(SAMPLES * SAMPLES)
	var step := Defs.CHUNK_SIZE / float(SAMPLES - 1)
	for j in SAMPLES:
		for i in SAMPLES:
			var h: float = _world.height_at(origin.x + i * step, origin.y + j * step)
			heights[j * SAMPLES + i] = clampf((h - HEIGHT_MIN) / HEIGHT_RANGE, 0.0, 1.0)
	_terrain = ChunkedTerrain3D.new()
	_terrain.centered = false
	_terrain.size = Vector2(Defs.CHUNK_SIZE, Defs.CHUNK_SIZE)
	_terrain.height_scale = HEIGHT_RANGE
	_terrain.height_offset = HEIGHT_MIN
	_terrain.chunk_quads = 16
	_terrain.lod_count = 3
	_terrain.lod_distance = 70.0
	_terrain.skirt_depth = 3.0
	_terrain.collision_enabled = false # The server decides where players can stand.
	_terrain.cast_shadows = false
	_terrain.update_interval = 0.5
	_terrain.material = ground_material()
	_terrain.set_height_data(heights, Vector2i(SAMPLES, SAMPLES))
	add_child(_terrain)


## Mesh of a group. Kinds with a number ("tree:3", "building:5") are variants; the catalog picks the model installed for it,
## and each branch falls back to the Kenney or procedural models when its packs are missing.
func _mesh_for(kind: String) -> Mesh:
	var base: String = kind.get_slice(":", 0)
	var variant: int = int(kind.get_slice(":", 1)) if kind.contains(":") else 0
	var picked: Mesh = null
	match base:
		"tree":
			if _use_nature and variant < Assets.TREE_FILES.size():
				var tree_file: String = Assets.TREE_FILES[variant]
				return Foliage.swayed(Assets.nature_mesh(tree_file), "tree:" + tree_file, 0.22)
			if ModelCatalog.has_painted_trees() and _use_nature:
				var painted: Mesh = ModelCatalog.painted_tree(variant - Assets.TREE_FILES.size())
				if painted != null:
					return Foliage.swayed(painted, "painted:%d" % variant, 0.2)
			if not _use_nature:
				return Assets.tree_meshes()[variant % Assets.tree_meshes().size()]
		"rock":
			if _use_nature and variant < Assets.ROCK_FILES.size():
				return Assets.nature_mesh(Assets.ROCK_FILES[variant])
			if ModelCatalog.has_stones():
				picked = ModelCatalog.stone(variant - Assets.ROCK_FILES.size())
			elif _use_nature:
				return Assets.nature_mesh(Assets.ROCK_FILES[variant % Assets.ROCK_FILES.size()])
		"ore":
			picked = ModelCatalog.entry_mesh(ModelCatalog.pick("crystals", ModelCatalog.CRYSTALS, variant))
			if picked == null and _use_nature:
				return Assets.nature_mesh(Assets.ROCK_FILES[variant % Assets.ROCK_FILES.size()])
		"bush":
			if _use_nature:
				return Foliage.swayed(Assets.nature_mesh("Bush_Common"), "bush", 0.08)
		"berry":
			if _use_nature:
				return Foliage.swayed(Assets.nature_mesh("Bush_Common_Flowers"), "berry", 0.08)
		"building":
			picked = ModelCatalog.entry_mesh(ModelCatalog.pick("houses", ModelCatalog.HOUSES, variant))
			if picked == null:
				return Assets.building_mesh(variant)
		"wall":
			picked = ModelCatalog.entry_mesh(ModelCatalog.pick("walls", ModelCatalog.WALLS, variant))
			if picked == null:
				return Assets.mesh("fps/wall-high")
		"tower":
			picked = ModelCatalog.entry_mesh(ModelCatalog.pick("towers", ModelCatalog.TOWERS, variant))
			if picked == null:
				return Assets.building_mesh(4)
		"workbench":
			if _use_village:
				return Assets.village_mesh(Assets.STATION_FILE)
			return Meshes.get_mesh("workbench")
		"prop":
			picked = ModelCatalog.entry_mesh(ModelCatalog.pick("props", ModelCatalog.PROPS, variant))
			if picked == null:
				return Meshes.get_mesh("crate")
		"ruin":
			picked = ModelCatalog.entry_mesh(ModelCatalog.pick("ruins", ModelCatalog.RUINS, variant))
			if picked == null:
				return Assets.building_mesh(variant)
		"crate":
			picked = ModelCatalog.entry_mesh(ModelCatalog.pick("crates", ModelCatalog.CRATES, variant))
			if picked == null:
				return Meshes.get_mesh("crate")
	if picked != null:
		return picked
	return Meshes.get_mesh(base)


## Size multiplier of one instance. Catalog meshes are baked to meters already, so this is only the variation between
## instances and the difference between a structure's own scale and the nominal one the mesh was baked for.
func _size_for(kind: String, node: Dictionary, rng: RandomNumberGenerator) -> float:
	var base: String = kind.get_slice(":", 0)
	var variant: int = int(kind.get_slice(":", 1)) if kind.contains(":") else 0
	var baked: bool = _is_baked(base, variant)
	match base:
		"tree":
			if _use_nature:
				return rng.randf_range(0.85, 1.25)
			return Assets.TREE_SCALE * rng.randf_range(0.85, 1.3)
		"rock":
			if baked or _use_nature:
				return rng.randf_range(0.7, 1.05)
			return rng.randf_range(0.8, 1.3)
		"ore":
			return rng.randf_range(0.8, 1.15)
		"bush", "berry":
			return rng.randf_range(0.8, 1.1) if _use_nature else 1.0
		"building":
			return float(node["scale"]) / 6.0 if baked else float(node["scale"])
		"wall":
			return float(node["scale"]) / 3.0 if baked else float(node["scale"])
		"tower":
			return float(node["scale"]) / 5.0 if baked else float(node["scale"])
		"workbench":
			return 2.2 if _use_village else 1.0
		"prop":
			return float(node.get("scale", 1.5)) / 1.5 if baked else 0.5
		"ruin", "crate":
			return 1.0
	return 1.0


## Whether the model of a kind came from the catalog (already in meters) rather than from the old fallback sets.
func _is_baked(base: String, variant: int) -> bool:
	match base:
		"building":
			return not ModelCatalog.available("houses", ModelCatalog.HOUSES).is_empty()
		"wall":
			return not ModelCatalog.available("walls", ModelCatalog.WALLS).is_empty()
		"tower":
			return not ModelCatalog.available("towers", ModelCatalog.TOWERS).is_empty()
		"prop":
			return not ModelCatalog.available("props", ModelCatalog.PROPS).is_empty()
		"rock":
			return variant >= Assets.ROCK_FILES.size() and ModelCatalog.has_stones()
	return false


func _build_objects(data: Dictionary) -> void:
	var origin := WorldGen.cell_origin(cell)
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldGen.mix(cell.x, cell.y, 99)
	var tree_variants: int = Assets.tree_meshes().size()
	if _use_nature:
		tree_variants = Assets.TREE_FILES.size() + (ModelCatalog.PAINTED_TREES.size() if ModelCatalog.has_painted_trees() else 0)
	var rock_variants: int = Assets.ROCK_FILES.size() + (ModelCatalog.STONES.size() if ModelCatalog.has_stones() else 0)
	var crystal_count: int = ModelCatalog.available("crystals", ModelCatalog.CRYSTALS).size()
	# Group everything that shares a mesh, so each group is one draw call.
	var by_kind: Dictionary = {}
	for node in data["nodes"]:
		var kind: String = node["kind"]
		var variant: int = WorldGen.mix(int(node["id"]), 3, 5)
		if kind == "tree":
			kind = "tree:%d" % (variant % tree_variants)
		elif kind == "rock" and (_use_nature or rock_variants > Assets.ROCK_FILES.size()):
			kind = "rock:%d" % (variant % rock_variants)
		elif kind == "ore" and crystal_count > 0:
			kind = "ore:%d" % (variant % crystal_count)
		elif kind == "ore" and _use_nature:
			kind = "ore:%d" % (variant % Assets.ROCK_FILES.size())
		by_kind.get_or_add(kind, []).append(node)
	for crate in data["crates"]:
		by_kind.get_or_add("crate:%d" % int(crate.get("variant", WorldGen.mix(int(crate["id"]), 4, 6))), []).append(crate)
	var windmills: Array = []
	for structure in data["structures"]:
		var structure_kind: String = structure["kind"]
		if structure_kind == "windmill":
			windmills.append(structure)
			continue
		var key: String = structure_kind
		if structure_kind != "workbench":
			key = "%s:%d" % [structure_kind, int(structure["variant"])]
		by_kind.get_or_add(key, []).append(structure)
	for prop in data.get("props", []):
		by_kind.get_or_add("prop:%d" % int(prop["variant"]), []).append(prop)
	for kind in by_kind:
		var list: Array = by_kind[kind]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = _mesh_for(kind)
		multimesh.instance_count = list.size()
		var index: Dictionary = {}
		var transforms: Array = []
		var is_building: bool = kind.begins_with("wall") or kind.begins_with("building:") or kind.begins_with("tower") or kind == "workbench" or kind.begins_with("ruin:")
		for i in list.size():
			var node: Dictionary = list[i]
			var size: float = _size_for(kind, node, rng)
			var yaw: float = float(node["yaw"]) if node.has("yaw") else rng.randf() * TAU
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size)
			var sink: float = 0.05 if (is_building or kind == "crate") else 0.0
			var transform := Transform3D(basis, Vector3(node["x"] - origin.x, node["y"] - sink, node["z"] - origin.y))
			multimesh.set_instance_transform(i, transform)
			# The tier shows as a tint on the Kenney meshes (which use vertex colors).
			var tier: int = node.get("tier", 1)
			if kind.begins_with("rock") or kind.begins_with("ore"):
				multimesh.set_instance_color(i, Color.WHITE.lerp(Color(0.8, 0.85, 1.0), (tier - 1) * 0.2))
			else:
				multimesh.set_instance_color(i, Color.WHITE.darkened((tier - 1) * 0.07) if kind.begins_with("tree:") else Color.WHITE)
			if node.has("id"):
				index[node["id"]] = i
			transforms.append(transform)
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (kind.begins_with("tree:") or kind.begins_with("building:") or kind.begins_with("wall") or kind.begins_with("tower") or kind.begins_with("ruin:")) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _use_nature and kind.begins_with("ore:") and crystal_count == 0:
			instance.material_override = _ore_material(multimesh.mesh)
		add_child(instance)
		_groups[kind] = {"multimesh": multimesh, "index": index, "transforms": transforms}
	if _use_nature:
		_build_decor(origin, rng)
	_build_windmills(windmills, origin)
	_build_npcs(data.get("npcs", []))


var _sails: Array = [] # [{"node": Node3D, "axis": Vector3, "speed": float}]


## Windmills are single objects with sails that turn.
func _build_windmills(windmills: Array, origin: Vector2) -> void:
	if windmills.is_empty():
		return
	var model: Dictionary = ModelCatalog.windmill()
	for item in windmills:
		var root := Node3D.new()
		root.position = Vector3(float(item["x"]) - origin.x, float(item["y"]) - 0.05, float(item["z"]) - origin.y)
		root.rotation.y = float(item["yaw"])
		add_child(root)
		if model.is_empty():
			var mesh := MeshInstance3D.new()
			mesh.mesh = Assets.building_mesh(4)
			mesh.scale = Vector3.ONE * 4.0
			root.add_child(mesh)
			continue
		var body := MeshInstance3D.new()
		body.mesh = model["body"]
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(body)
		# The sails turn about their own centre: a pivot node at that point, the mesh moved back by the same amount.
		var pivot := Node3D.new()
		pivot.position = model["pivot"]
		root.add_child(pivot)
		var sails := MeshInstance3D.new()
		sails.mesh = model["sails"]
		sails.position = -Vector3(model["pivot"])
		pivot.add_child(sails)
		_sails.append({"node": pivot, "axis": model["axis"], "speed": 0.5 + float(WorldGen.mix(int(item["x"]), int(item["z"]), 8, 1) % 40) / 100.0})
	set_process(true)


func _process(delta: float) -> void:
	for sail in _sails:
		(sail["node"] as Node3D).rotate_object_local(sail["axis"], sail["speed"] * delta)


## The people of the settlements: standing, sitting, working, each with a name and a role above their head.
func _build_npcs(npcs: Array) -> void:
	for npc in npcs:
		var model := CharacterModel.new()
		add_child(model)
		model.setup(Color.WHITE, 2.0, 1.0, str(npc["model"]) if Assets.has_characters() else "", false)
		model.position = Vector3(float(npc["x"]), float(npc["y"]), float(npc["z"])) - Vector3(_world_origin().x, 0.0, _world_origin().y)
		model.rotation.y = float(npc["yaw"])
		model.play_fixed(str(npc["animation"]))
		var label := Label3D.new()
		label.text = "%s\n%s" % [npc["name"], npc["title"]]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 30
		label.pixel_size = 0.0065
		label.outline_size = 8
		label.modulate = Color(1.0, 0.92, 0.65) if str(npc["role"]) == "trader" else Color(0.9, 0.95, 1.0)
		label.position = Vector3(0, 2.7, 0)
		label.visibility_range_end = 26.0
		model.add_child(label)


func _world_origin() -> Vector2:
	return WorldGen.cell_origin(cell)


## Ore is the same rock tinted like copper, so it reads as something worth mining.
static var _ore_material_cache: StandardMaterial3D

static func _ore_material(mesh: Mesh) -> Material:
	if _ore_material_cache == null:
		var base := mesh.surface_get_material(0)
		_ore_material_cache = (base as StandardMaterial3D).duplicate() as StandardMaterial3D if base is StandardMaterial3D else StandardMaterial3D.new()
		_ore_material_cache.albedo_color = Color(1.0, 0.62, 0.35)
	return _ore_material_cache


# Decoration that exists only on the client: it never blocks anyone, so the server knows nothing about it.
const DECOR := [
	{"file": "Grass_Common_Tall", "count": 70, "scale": [0.9, 1.4], "biomes": ["forest", "plains", "swamp"]},
	{"file": "Grass_Wispy_Short", "count": 70, "scale": [0.9, 1.5], "biomes": ["forest", "plains", "beach"]},
	{"file": "Fern_1", "count": 14, "scale": [0.8, 1.3], "biomes": ["forest", "swamp"]},
	{"file": "Flower_3_Group", "count": 12, "scale": [0.8, 1.2], "biomes": ["plains", "forest"]},
	{"file": "Flower_4_Group", "count": 10, "scale": [0.8, 1.2], "biomes": ["plains"]},
	{"file": "Mushroom_Common", "count": 6, "scale": [0.9, 1.6], "biomes": ["forest", "swamp"]},
	{"file": "Pebble_Round_1", "count": 18, "scale": [0.8, 1.8], "biomes": ["forest", "plains", "beach", "mountain"]},
	{"file": "Pebble_Square_2", "count": 12, "scale": [0.8, 1.8], "biomes": ["plains", "beach", "mountain"]},
]


func _build_decor(origin: Vector2, rng: RandomNumberGenerator) -> void:
	var center := origin + Vector2.ONE * Defs.CHUNK_SIZE * 0.5
	if center.length() < Defs.HUB_SAFE_RADIUS + 30.0:
		return # The hub is paved.
	for entry in DECOR:
		var mesh: Mesh = Foliage.swayed(Assets.nature_mesh(entry["file"]), "decor:" + String(entry["file"]), 0.0 if String(entry["file"]).begins_with("Pebble") else 0.12)
		if mesh == null:
			continue
		var spots: Array = []
		for i in int(entry["count"]):
			var x := origin.x + rng.randf() * Defs.CHUNK_SIZE
			var z := origin.y + rng.randf() * Defs.CHUNK_SIZE
			if _world.is_water(x, z) or not (_world.biome_at(x, z) in entry["biomes"]):
				continue
			spots.append(Vector3(x, _world.height_at(x, z), z))
		if spots.is_empty():
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = spots.size()
		for i in spots.size():
			var size := rng.randf_range(float(entry["scale"][0]), float(entry["scale"][1]))
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size)
			multimesh.set_instance_transform(i, Transform3D(basis, Vector3(spots[i].x - origin.x, spots[i].y, spots[i].z - origin.y)))
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_end = 110.0 # Small things are not worth drawing far away.
		add_child(instance)
	# Logs, stumps, painted flowers and the odd standing stone from the loose collections.
	for entry in ModelCatalog.available("decor", ModelCatalog.DECOR_EXTRA):
		var extra_mesh: Mesh = ModelCatalog.entry_mesh(entry)
		if extra_mesh == null:
			continue
		var places: Array = []
		for i in int(entry["count"]):
			var x := origin.x + rng.randf() * Defs.CHUNK_SIZE
			var z := origin.y + rng.randf() * Defs.CHUNK_SIZE
			if _world.is_water(x, z) or not (_world.biome_at(x, z) in entry["biomes"]):
				continue
			places.append(Vector3(x, _world.height_at(x, z), z))
		if places.is_empty():
			continue
		var extra := MultiMesh.new()
		extra.transform_format = MultiMesh.TRANSFORM_3D
		extra.mesh = extra_mesh
		extra.instance_count = places.size()
		for i in places.size():
			var scale_factor := rng.randf_range(0.8, 1.3)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale_factor)
			extra.set_instance_transform(i, Transform3D(basis, Vector3(places[i].x - origin.x, places[i].y, places[i].z - origin.y)))
		var extra_instance := MultiMeshInstance3D.new()
		extra_instance.multimesh = extra
		extra_instance.visibility_range_end = 140.0
		add_child(extra_instance)


## Hides depleted nodes and opened crates. `hidden_ids` is the set of ids the server says are gone.
func apply_state(hidden_ids: Dictionary) -> void:
	for kind in _groups:
		var group: Dictionary = _groups[kind]
		for id in group["index"]:
			var should_hide: bool = hidden_ids.has(id)
			if should_hide == _hidden.has(id):
				continue
			var i: int = group["index"][id]
			if should_hide:
				_hidden[id] = true
				group["multimesh"].set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.001), group["transforms"][i].origin))
			else:
				_hidden.erase(id)
				group["multimesh"].set_instance_transform(i, group["transforms"][i])
