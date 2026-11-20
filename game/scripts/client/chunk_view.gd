extends Node3D
## The visual side of one world chunk: its terrain and every tree, rock, bush and crate in it.
## Nothing here is sent over the network. It is built from the seed, and only the "depleted" and
## "opened" flags from the server change what is shown.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Meshes = preload("res://scripts/client/meshes.gd")
const Assets = preload("res://scripts/client/assets.gd")
const Foliage = preload("res://scripts/client/foliage.gd")

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


func _mesh_for(kind: String) -> Mesh:
	if _use_nature:
		# The downloaded Quaternius nature kit.
		if kind.begins_with("tree:"):
			var tree_file: String = Assets.TREE_FILES[int(kind.get_slice(":", 1)) % Assets.TREE_FILES.size()]
			return Foliage.swayed(Assets.nature_mesh(tree_file), "tree:" + tree_file, 0.22)
		if kind.begins_with("rock:") or kind.begins_with("ore:"):
			return Assets.nature_mesh(Assets.ROCK_FILES[int(kind.get_slice(":", 1)) % Assets.ROCK_FILES.size()])
		if kind == "bush":
			return Foliage.swayed(Assets.nature_mesh("Bush_Common"), "bush", 0.08)
		if kind == "berry":
			return Foliage.swayed(Assets.nature_mesh("Bush_Common_Flowers"), "berry", 0.08)
	if _use_village:
		if kind.begins_with("building:"):
			return Assets.pack_building(int(kind.get_slice(":", 1)))["mesh"]
		if kind == "wall":
			return Assets.village_mesh("EA03_Fence_Wall_01b")
		if kind == "crate":
			return Assets.village_mesh("EA03_Prop_Container_Crate_01a")
	if kind.begins_with("tree:"):
		return Assets.tree_meshes()[int(kind.get_slice(":", 1))]
	if kind.begins_with("building:"):
		return Assets.building_mesh(int(kind.get_slice(":", 1)))
	if kind == "wall":
		return Assets.mesh("fps/wall-high")
	if kind.begins_with("rock:") or kind.begins_with("ore:"):
		return Meshes.get_mesh(kind.get_slice(":", 0))
	return Meshes.get_mesh(kind)


## Size of one instance of a group, and (for pack models) the yaw-independent ground offset.
func _size_for(kind: String, node: Dictionary, rng: RandomNumberGenerator) -> float:
	if _use_nature and kind.begins_with("tree:"):
		return rng.randf_range(0.85, 1.25)
	if _use_nature and (kind.begins_with("rock:") or kind.begins_with("ore:")):
		return rng.randf_range(0.65, 1.0) * (1.0 if kind.begins_with("rock:") else 0.8)
	if _use_nature and (kind == "bush" or kind == "berry"):
		return rng.randf_range(0.8, 1.1)
	if _use_village and kind.begins_with("building:"):
		return float(Assets.pack_building(int(kind.get_slice(":", 1)))["scale"])
	if _use_village and kind == "wall":
		return Assets.fit_scale(_mesh_for(kind), Assets.WALL_LENGTH)
	if _use_village and kind == "crate":
		return 1.5
	if kind.begins_with("tree:"):
		return Assets.TREE_SCALE * rng.randf_range(0.85, 1.3)
	if kind.begins_with("rock:") or kind.begins_with("ore:") or kind == "rock" or kind == "ore":
		return rng.randf_range(0.8, 1.3)
	if kind == "wall" or kind.begins_with("building:"):
		return float(node["scale"])
	return 1.0


func _build_objects(data: Dictionary) -> void:
	var origin := WorldGen.cell_origin(cell)
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldGen.mix(cell.x, cell.y, 99)
	var tree_variants: int = Assets.TREE_FILES.size() if _use_nature else Assets.tree_meshes().size()
	var rock_variants: int = Assets.ROCK_FILES.size()
	# Group everything that shares a mesh, so each group is one draw call.
	var by_kind: Dictionary = {}
	for node in data["nodes"]:
		var kind: String = node["kind"]
		var variant: int = WorldGen.mix(int(node["id"]), 3, 5)
		if kind == "tree":
			kind = "tree:%d" % (variant % tree_variants)
		elif _use_nature and (kind == "rock" or kind == "ore"):
			kind = "%s:%d" % [kind, variant % rock_variants]
		by_kind.get_or_add(kind, []).append(node)
	for crate in data["crates"]:
		by_kind.get_or_add("crate", []).append(crate)
	for structure in data["structures"]:
		var key: String = "wall" if structure["kind"] == "wall" else "building:%d" % structure["variant"]
		by_kind.get_or_add(key, []).append(structure)
	for kind in by_kind:
		var list: Array = by_kind[kind]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = _mesh_for(kind)
		multimesh.instance_count = list.size()
		var index: Dictionary = {}
		var transforms: Array = []
		var is_building: bool = kind == "wall" or kind.begins_with("building:")
		for i in list.size():
			var node: Dictionary = list[i]
			var size: float = _size_for(kind, node, rng)
			var yaw: float = float(node["yaw"]) if is_building else rng.randf() * TAU
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size)
			var sink: float = 0.05 if (is_building or kind == "crate") else 0.0
			var transform := Transform3D(basis, Vector3(node["x"] - origin.x, node["y"] - sink, node["z"] - origin.y))
			multimesh.set_instance_transform(i, transform)
			# The tier shows as a tint on the Kenney meshes (which use vertex colors).
			var tier: int = node.get("tier", 1)
			if kind in ["rock", "ore"]:
				multimesh.set_instance_color(i, Color.WHITE.lerp(Color(0.8, 0.85, 1.0), (tier - 1) * 0.2))
			else:
				multimesh.set_instance_color(i, Color.WHITE.darkened((tier - 1) * 0.07) if kind.begins_with("tree:") else Color.WHITE)
			index[node["id"]] = i
			transforms.append(transform)
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (kind.begins_with("tree:") or kind.begins_with("building:") or kind == "wall") else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _use_nature and kind.begins_with("ore:"):
			instance.material_override = _ore_material(multimesh.mesh)
		add_child(instance)
		_groups[kind] = {"multimesh": multimesh, "index": index, "transforms": transforms}
	if _use_nature:
		_build_decor(origin, rng)


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
