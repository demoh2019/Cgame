extends Node3D
## The visual side of one world chunk: its terrain and every tree, rock, bush and crate in it.
## Nothing here is sent over the network. It is built from the seed, and only the "depleted" and
## "opened" flags from the server change what is shown.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Meshes = preload("res://scripts/client/meshes.gd")
const Assets = preload("res://scripts/client/assets.gd")

const SAMPLES := 33 # Heights per side: one every 2 m.
const HEIGHT_MIN := -45.0
const HEIGHT_RANGE := 220.0
const GROUND_SHADER := """
shader_type spatial;
varying vec3 world_position;
varying vec3 world_normal;
uniform float water_level = 0.0;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
void fragment() {
	float h = world_position.y;
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	vec3 grass = vec3(0.28, 0.46, 0.2);
	vec3 dry = vec3(0.5, 0.5, 0.26);
	vec3 sand = vec3(0.76, 0.69, 0.47);
	vec3 rock = vec3(0.46, 0.44, 0.42);
	vec3 snow = vec3(0.93, 0.95, 0.98);
	float patch = hash21(floor(world_position.xz * 0.35));
	vec3 base = mix(grass, dry, smoothstep(0.35, 0.9, patch) * 0.55);
	base = mix(sand, base, smoothstep(0.5, 2.2, h));
	base = mix(base, rock, smoothstep(0.22, 0.5, slope));
	base = mix(base, rock * 0.9, smoothstep(38.0, 55.0, h));
	base = mix(base, snow, smoothstep(85.0, 105.0, h) * (1.0 - smoothstep(0.35, 0.6, slope)));
	// Wet ground at the waterline.
	base = mix(base * 0.7, base, smoothstep(-1.0, 0.8, h));
	ALBEDO = base * (0.92 + 0.16 * hash21(floor(world_position.xz * 1.5)));
	ROUGHNESS = 0.95;
}
"""

static var _ground_material: ShaderMaterial

var cell: Vector2i
var _world
var _terrain
var _groups: Dictionary = {} # kind -> {"multimesh": MultiMesh, "index": {node_id: i}, "transforms": [...]}
var _hidden: Dictionary = {} # node id -> true, currently hidden


static func ground_material() -> ShaderMaterial:
	if _ground_material == null:
		var shader := Shader.new()
		shader.code = GROUND_SHADER
		_ground_material = ShaderMaterial.new()
		_ground_material.shader = shader
	return _ground_material


func build(p_world, p_cell: Vector2i) -> void:
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
	if kind.begins_with("tree:"):
		return Assets.tree_meshes()[int(kind.get_slice(":", 1))]
	if kind.begins_with("building:"):
		return Assets.building_mesh(int(kind.get_slice(":", 1)))
	if kind == "wall":
		return Assets.mesh("fps/wall-high")
	return Meshes.get_mesh(kind)


func _build_objects(data: Dictionary) -> void:
	var origin := WorldGen.cell_origin(cell)
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldGen.mix(cell.x, cell.y, 99)
	var tree_variants: int = Assets.tree_meshes().size()
	# Group everything that shares a mesh, so each group is one draw call.
	var by_kind: Dictionary = {}
	for node in data["nodes"]:
		var kind: String = node["kind"]
		if kind == "tree":
			kind = "tree:%d" % (WorldGen.mix(int(node["id"]), 3, 5) % tree_variants)
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
		for i in list.size():
			var node: Dictionary = list[i]
			var size := 1.0
			var yaw := rng.randf() * TAU
			if kind.begins_with("tree:"):
				size = Assets.TREE_SCALE * rng.randf_range(0.85, 1.3)
			elif kind in ["rock", "ore"]:
				size = rng.randf_range(0.8, 1.3)
			elif kind == "wall" or kind.begins_with("building:"):
				size = float(node["scale"])
				yaw = float(node["yaw"])
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size)
			var transform := Transform3D(basis, Vector3(node["x"] - origin.x, node["y"] - (0.05 if size > 2.0 and not kind.begins_with("tree:") else 0.0), node["z"] - origin.y))
			multimesh.set_instance_transform(i, transform)
			# The tier shows as a tint: higher tiers are darker and bluer.
			var tier: int = node.get("tier", 1)
			if kind in ["rock", "ore"]:
				multimesh.set_instance_color(i, Color.WHITE.lerp(Color(0.8, 0.85, 1.0), (tier - 1) * 0.2))
			else:
				multimesh.set_instance_color(i, Color.WHITE.darkened((tier - 1) * 0.07) if kind.begins_with("tree:") else Color.WHITE)
			index[node["id"]] = i
			transforms.append(transform)
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		_groups[kind] = {"multimesh": multimesh, "index": index, "transforms": transforms}


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
