extends RefCounted
## Vertex-shader cloth for outpost banners (Unity Cloth component / Unreal Chaos Cloth, in a cheap analytic form):
## a subdivided plane pinned along the pole edge whose free end ripples in the weather wind. The waving travels
## down the flag, the free edge droops with gravity and lifts with wind strength; no CPU work per frame.
## Wind comes from the same global the vegetation uses (aa_vegetation_wind: xy direction, z strength).

const SEGMENTS := [0, 6, 12, 20] # Width subdivisions per quality tier; 0 keeps the rigid flag on Low.
const SIZE := Vector2(2.4, 1.5)

const SHADER_CODE := """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;
global uniform vec3 aa_vegetation_wind;
uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float flag_width = 2.4;
varying float fold;
void vertex() {
	// UV.x is 0 at the pole and 1 at the free edge; the pinned edge never moves.
	float free_end = UV.x * UV.x;
	float power = clamp(aa_vegetation_wind.z, 0.0, 1.0);
	float strength = 0.12 + power * 0.88;
	float phase = TIME * (2.2 + power * 3.0) - UV.x * 7.0 - UV.y * 1.7;
	float ripple = sin(phase) * 0.22 + sin(phase * 2.3 + 1.7) * 0.07;
	VERTEX.z += ripple * free_end * strength * flag_width * 0.35;
	// Cloth hangs: the free edge sags down, less so when the wind holds it out.
	VERTEX.y -= free_end * (1.0 - power * 0.7) * 0.28;
	VERTEX.x -= free_end * (0.04 + 0.1 * strength);
	fold = cos(phase) * free_end * strength;
	NORMAL = normalize(vec3(-fold * 0.6, 0.0, 1.0));
}
void fragment() {
	ALBEDO = albedo.rgb * (0.88 + fold * 0.14);
	EMISSION = emission_color;
}
"""

static var _shader: Shader


static func segments(level: int) -> int:
	return SEGMENTS[clampi(level, 0, SEGMENTS.size() - 1)]


## A plane facing +Z with UV.x along the free direction, origin at the pole edge (x from 0 to width).
static func build_mesh(width_segments: int) -> ArrayMesh:
	var cols := maxi(width_segments, 1)
	var rows := 3
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	for j in rows + 1:
		for i in cols + 1:
			var u := float(i) / cols
			var v := float(j) / rows
			vertices.append(Vector3(u * SIZE.x, (0.5 - v) * SIZE.y, 0.0))
			uvs.append(Vector2(u, v))
			normals.append(Vector3(0, 0, 1))
	var indices := PackedInt32Array()
	for j in rows:
		for i in cols:
			var a := j * (cols + 1) + i
			var b := a + 1
			var c := a + cols + 1
			var d := c + 1
			indices.append_array([a, c, b, b, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func make_material() -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("flag_width", SIZE.x)
	return material


## Replace a rigid flag mesh with the cloth one; returns the ShaderMaterial (null on Low, flag unchanged).
static func upgrade(flag: MeshInstance3D, level: int) -> ShaderMaterial:
	var count := segments(level)
	if count <= 0 or flag == null:
		return null
	flag.mesh = build_mesh(count)
	flag.position.x -= SIZE.x * 0.5 # The box was centered on its position; the cloth is pinned at the pole.
	var material := make_material()
	flag.material_override = material
	flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return material


# --- Simulated cloth (High/Ultra with the native cgame_softbody module) -----------------------------------------------
# On High and Ultra, when the engine provides ClothInstance3D + CgameXPBDCloth, the banner becomes a real XPBD cloth
# pinned along the pole edge and blown by the weather wind. The flag MeshInstance3D keeps its StandardMaterial3D
# (so outpost tinting is unchanged) and hides its own mesh; a ClothInstance3D child named "Cloth" renders the sim with
# the same material. Lower tiers and engines without the module keep the cheap shader path above.

const SoftbodyFacade = preload("res://scripts/native/cgame_softbody_facade.gd")
const VegetationWind = preload("res://scripts/client/vegetation_wind.gd")

const SIMULATED_MIN_LEVEL := 2 # High.
const CLOTH_NODE := "Cloth"
const WIND_BASE := 0.8 # m/s of breeze even in calm weather, so the banner never hangs dead.
const WIND_SCALE := 7.0 # m/s at full weather strength.


## Whether `level` gets the native XPBD cloth (High/Ultra on an engine built with cgame_softbody).
static func can_simulate(level: int) -> bool:
	return level >= SIMULATED_MIN_LEVEL and ClassDB.class_exists("ClothInstance3D") and ClassDB.class_exists("CgameXPBDCloth")


## Picks the best flag for the quality tier: native cloth sim, shader cloth, or the rigid box (Low).
## Returns "simulated", "shader" or "rigid".
static func apply(flag: MeshInstance3D, level: int) -> String:
	if flag != null and can_simulate(level) and upgrade_simulated(flag, level) != null:
		return "simulated"
	return "shader" if upgrade(flag, level) != null else "rigid"


## Grid size (width cells, height cells) for the simulated banner at `level`.
static func sim_grid(level: int) -> Vector2i:
	var cols: int = maxi(segments(level), 4)
	var rows: int = maxi(int(round(SIZE.y / (SIZE.x / float(cols)))), 2)
	return Vector2i(cols, rows)


## World-space wind for the cloth from the shared vegetation wind (xy direction, z strength 0..1).
static func wind_vector(vegetation_wind: Vector3) -> Vector3:
	var dir := Vector3(vegetation_wind.x, 0.0, vegetation_wind.y)
	if dir.length_squared() < 0.0001:
		dir = Vector3(0.0, 0.0, 1.0)
	return dir.normalized() * (WIND_BASE + clampf(vegetation_wind.z, 0.0, 1.0) * WIND_SCALE)


## Replaces the flag mesh with a native ClothInstance3D child. Returns the cloth node, or null (flag unchanged) when
## the native classes are missing. The grid is built in world space once the node enters the scene tree.
static func upgrade_simulated(flag: MeshInstance3D, level: int) -> Node3D:
	if flag == null or not ClassDB.class_exists("ClothInstance3D"):
		return null
	var cloth: RefCounted = SoftbodyFacade.make_cloth()
	if cloth == null or not cloth.has_method("drive"): # GDScript fallback cloth cannot feed ClothInstance3D.
		return null
	var node: Node3D = SoftbodyFacade.make_cloth_node(cloth)
	if node == null:
		return null
	var grid := sim_grid(level)
	node.name = CLOTH_NODE
	node.set_meta("grid", grid)
	node.set("substeps", 4 if level >= 3 else 3)
	cloth.set("iterations", 2)
	cloth.set("drag", 0.4)
	cloth.set("wind", wind_vector(VegetationWind.current))
	flag.position.x -= SIZE.x * 0.5 # Same pole pinning as the shader path: origin at the pole edge.
	flag.mesh = null
	var material := flag.material_override as StandardMaterial3D
	if material != null:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	(node as GeometryInstance3D).material_override = flag.material_override
	(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.tree_entered.connect(build_grid.bind(node), CONNECT_ONE_SHOT)
	flag.add_child(node)
	return node


## Lays the particle grid out at the node's world transform (x along the banner, y down) and pins the pole edge.
## Runs automatically when the cloth node enters the scene tree; callable directly (tests, re-placing a banner).
static func build_grid(node: Node3D) -> void:
	var cloth: Object = node.call("get_cloth")
	if cloth == null:
		return
	var grid: Vector2i = node.get_meta("grid", Vector2i(8, 5))
	var spacing: float = SIZE.x / float(grid.x)
	var origin: Transform3D = _world_transform(node) * Transform3D(Basis(), Vector3(0.0, SIZE.y * 0.5, 0.0))
	cloth.call("setup_grid", grid.x, grid.y, spacing, origin, 0.05)
	for j in grid.y + 1:
		var index: int = cloth.call("index_of", 0, j)
		cloth.call("pin", index, origin * Vector3(0.0, -float(j) * spacing, 0.0))
	node.call("rebuild_mesh")


## Global transform, also for nodes not (yet) inside a running tree: composes the Node3D parent chain.
static func _world_transform(node: Node3D) -> Transform3D:
	if node.is_inside_tree():
		return node.global_transform
	var xf: Transform3D = node.transform
	var parent: Node = node.get_parent()
	while parent is Node3D:
		xf = (parent as Node3D).transform * xf
		parent = parent.get_parent()
	return xf


## Feeds the current weather wind to a simulated flag (no-op for shader/rigid flags). Cheap; call on refresh.
static func update_wind(flag: Node) -> void:
	if flag == null:
		return
	var node: Node = flag.get_node_or_null(CLOTH_NODE)
	if node == null:
		return
	var cloth: Object = node.call("get_cloth")
	if cloth != null:
		cloth.set("wind", wind_vector(VegetationWind.current))


static func tint(material: Material, color: Color) -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("albedo", color)
		(material as ShaderMaterial).set_shader_parameter("emission_color", Vector3(color.r, color.g, color.b) * 0.45)
