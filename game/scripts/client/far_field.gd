extends Node3D
## Distant landscape: what lies beyond the streamed chunks (about 150 m) out to ~850 m.
##  * A coarse far-terrain ring sampled from the same WorldGen.ground_at, coloured by biome, sitting
##    just under the real chunk terrain so near ground always wins.
##  * Forest HLOD: distant woods as one MultiMesh of IMPOSTORS — camera-facing cards whose
##    pictures are baked at start-up from the game's own tree models in an off-screen viewport.
## The ring is rebuilt incrementally (a few rows per frame) when the player has moved far enough,
## then swapped in at once, so it never hitches.

const Assets = preload("res://scripts/client/assets.gd")
const GRID := 72 # Vertices per side.
const SPACING := 24.0 # Metres between vertices: 72 x 24 = 1.7 km across.
const REBUILD_DISTANCE := 96.0
const ROWS_PER_FRAME := 4
const NEAR_HIDE := 140.0 # Inside this the real chunks are always loaded: sink the far mesh away.
const SINK := 0.8
const TREE_NEAR := 150.0 # Real trees are drawn inside this radius.
const IMPOSTOR_SIZE := 256
const IMPOSTOR_TREES := ["CommonTree_1", "CommonTree_3", "Pine_2", "Pine_4", "TwistedTree_1", "CommonTree_5"]
const BIOME_COLOURS := {
	"forest": Color(0.2, 0.31, 0.13), "plains": Color(0.38, 0.42, 0.2), "swamp": Color(0.22, 0.27, 0.16),
	"mountain": Color(0.42, 0.41, 0.38), "beach": Color(0.62, 0.56, 0.4), "water": Color(0.25, 0.3, 0.25),
}

var world
var _terrain: MeshInstance3D
var _trees: MultiMeshInstance3D
var _centre := Vector2(INF, INF)
var _job: Dictionary = {}
var _impostors: Texture2DArray
var _impostor_aspect: PackedFloat32Array = PackedFloat32Array()
var _baking := false
static var _tree_shader: Shader


func setup(p_world) -> void:
	world = p_world
	_terrain = MeshInstance3D.new()
	_terrain.name = "FarTerrain"
	var ground := StandardMaterial3D.new()
	ground.vertex_color_use_as_albedo = true
	ground.roughness = 1.0
	_terrain.material_override = ground
	_terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_terrain)
	_trees = MultiMeshInstance3D.new()
	_trees.name = "FarForest"
	_trees.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trees)
	_bake_impostors()


## Call every frame with the player's position.
func update(focus: Vector3) -> void:
	if world == null:
		return
	var here := Vector2(focus.x, focus.z)
	if _job.is_empty() and here.distance_to(_centre) > REBUILD_DISTANCE and not _baking:
		var snapped := (here / SPACING).round() * SPACING
		_job = {"centre": snapped, "row": 0, "heights": PackedFloat32Array(), "colours": PackedColorArray(), "trees": []}
	if not _job.is_empty():
		_advance_job()


func _advance_job() -> void:
	var centre: Vector2 = _job["centre"]
	var half: float = SPACING * float(GRID - 1) * 0.5
	var heights: PackedFloat32Array = _job["heights"]
	var colours: PackedColorArray = _job["colours"]
	var trees: Array = _job["trees"]
	for r in ROWS_PER_FRAME:
		var j: int = int(_job["row"])
		if j >= GRID:
			break
		for i in GRID:
			var x: float = centre.x - half + float(i) * SPACING
			var z: float = centre.y - half + float(j) * SPACING
			var d: float = Vector2(x, z).distance_to(centre)
			var h: float = world.ground_at(x, z)
			var biome: String = world.biome_at(x, z)
			heights.append(h - (40.0 if d < NEAR_HIDE else SINK))
			var colour: Color = BIOME_COLOURS.get(biome, BIOME_COLOURS["plains"])
			if h > 62.0:
				colour = colour.lerp(Color(0.85, 0.86, 0.9), smoothstep(62.0, 80.0, h)) # Snow caps.
			# Match the near ground's darker, patchy look (vertex colours are lit by the same sky).
			var mottle: float = float(world.mix(int(x), int(z), 5, 9) % 100) / 100.0
			colours.append(colour.darkened(0.42 - mottle * 0.12))
			# Forest HLOD: a seeded scatter matching the biome's density, outside the real-tree radius.
			if d > TREE_NEAR and h > 0.6:
				var per_cell: float = {"forest": 2.4, "swamp": 1.6, "plains": 0.35, "mountain": 0.6, "beach": 0.15}.get(biome, 0.0)
				var seed_value: int = world.mix(int(x), int(z), world.world_seed, 61)
				var n: int = int(per_cell) + (1 if float(seed_value % 1000) / 1000.0 < fmod(per_cell, 1.0) else 0)
				for k in n:
					var s2: int = world.mix(int(x), int(z), k, 62)
					var px: float = x + (float(s2 % 997) / 997.0 - 0.5) * SPACING
					var pz: float = z + (float((s2 / 997) % 991) / 991.0 - 0.5) * SPACING
					var kind: int = _kind_for(biome, s2)
					trees.append([Vector3(px, world.ground_at(px, pz), pz), kind, 0.8 + float(s2 % 50) / 100.0])
		_job["row"] = j + 1
	if int(_job["row"]) >= GRID:
		_finish_job()


func _kind_for(biome: String, seed_value: int) -> int:
	var options: Array = {"forest": [0, 1, 2, 5], "plains": [0, 1, 5], "swamp": [4, 1, 5], "mountain": [2, 3], "beach": [1, 3]}.get(biome, [0])
	return int(options[seed_value % options.size()])


func _finish_job() -> void:
	var centre: Vector2 = _job["centre"]
	var half: float = SPACING * float(GRID - 1) * 0.5
	var heights: PackedFloat32Array = _job["heights"]
	var colours: PackedColorArray = _job["colours"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in GRID:
		for i in GRID:
			st.set_color(colours[j * GRID + i])
			st.add_vertex(Vector3(-half + float(i) * SPACING, heights[j * GRID + i], -half + float(j) * SPACING))
	for j in GRID - 1:
		for i in GRID - 1:
			var a: int = j * GRID + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + GRID)
			st.add_index(a + 1)
			st.add_index(a + GRID + 1)
			st.add_index(a + GRID)
	st.generate_normals()
	_terrain.mesh = st.commit()
	_terrain.position = Vector3(centre.x, 0.0, centre.y)
	_build_trees(_job["trees"])
	_centre = centre
	_job = {}


func _build_trees(trees: Array) -> void:
	if _impostors == null or trees.is_empty():
		_trees.multimesh = null
		return
	var card := QuadMesh.new()
	card.size = Vector2(1.0, 1.0)
	card.center_offset = Vector3(0.0, 0.5, 0.0)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = card
	multimesh.instance_count = trees.size()
	for k in trees.size():
		var entry: Array = trees[k]
		var kind: int = entry[1]
		var height: float = 9.0 * float(entry[2])
		var width: float = height * (_impostor_aspect[kind] if kind < _impostor_aspect.size() else 0.7)
		multimesh.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(width, height, 1.0)), entry[0]))
		multimesh.set_instance_custom_data(k, Color(float(kind), 0.0, 0.0, 0.0))
	_trees.multimesh = multimesh
	if _trees.material_override == null:
		var material := ShaderMaterial.new()
		material.shader = _tree_shader_get()
		material.set_shader_parameter("impostors", _impostors)
		_trees.material_override = material


static func _tree_shader_get() -> Shader:
	if _tree_shader == null:
		_tree_shader = Shader.new()
		_tree_shader.code = """
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
uniform sampler2DArray impostors : source_color, filter_linear_mipmap;
varying float layer;
void vertex() {
	// Cylindrical billboard: the card turns about its own up axis to face the camera.
	vec3 world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), 1.0);
	vec3 to_cam = CAMERA_POSITION_WORLD - world_origin;
	to_cam.y = 0.0;
	to_cam = normalize(to_cam);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	vec3 world_pos = world_origin + right * VERTEX.x * scale.x + vec3(0.0, 1.0, 0.0) * VERTEX.y * scale.y;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world_pos, 1.0)).xyz;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(to_cam, 0.0)).xyz;
	layer = INSTANCE_CUSTOM.r;
}
void fragment() {
	vec4 c = texture(impostors, vec3(UV, layer));
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb * 0.9;
	ROUGHNESS = 0.95;
	BACKLIGHT = vec3(0.12, 0.16, 0.06);
}
"""
	return _tree_shader


## Bake one picture per tree model: an off-screen viewport with its own world, an orthographic
## camera framing the model's bounds, transparent background. Falls back to painted blobs.
func _bake_impostors() -> void:
	_baking = true
	var images: Array[Image] = []
	var meshes: Array = []
	for file in IMPOSTOR_TREES:
		var mesh: Mesh = Assets.nature_mesh(file) if Assets.has_nature() else null
		meshes.append(mesh)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(IMPOSTOR_SIZE, IMPOSTOR_SIZE)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.6, 0.55)
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.5, 0.0)
	viewport.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	viewport.add_child(camera)
	var holder := MeshInstance3D.new()
	viewport.add_child(holder)
	for mesh in meshes:
		var image: Image = null
		if mesh != null:
			holder.mesh = mesh
			var box: AABB = mesh.get_aabb()
			var extent: float = maxf(box.size.y, maxf(box.size.x, box.size.z)) * 1.04
			camera.size = extent
			var centre: Vector3 = box.get_center()
			camera.look_at_from_position(centre + Vector3(0, 0, extent * 2.0), centre, Vector3.UP)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			if not is_instance_valid(viewport):
				return
			image = viewport.get_texture().get_image()
			_impostor_aspect.append(clampf(maxf(box.size.x, box.size.z) / maxf(box.size.y, 0.01), 0.35, 1.2))
		if image == null:
			image = _blob_image()
			_impostor_aspect.append(0.65)
		image.convert(Image.FORMAT_RGBA8)
		_bleed_edges(image)
		image.generate_mipmaps()
		images.append(image)
	viewport.queue_free()
	_impostors = Texture2DArray.new()
	_impostors.create_from_images(images)
	_baking = false


## Spread colour into the transparent texels next to the silhouette, so mipmaps don't fringe white.
static func _bleed_edges(image: Image) -> void:
	var size: int = image.get_width()
	var copy := image.duplicate() as Image
	for y in size:
		for x in size:
			if copy.get_pixel(x, y).a > 0.1:
				continue
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var p: Vector2i = Vector2i(x, y) + (o as Vector2i)
				if p.x >= 0 and p.y >= 0 and p.x < size and p.y < size and copy.get_pixel(p.x, p.y).a > 0.5:
					var c: Color = copy.get_pixelv(p)
					image.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))
					break


static func _blob_image() -> Image:
	var image := Image.create(IMPOSTOR_SIZE, IMPOSTOR_SIZE, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	for y in IMPOSTOR_SIZE:
		for x in IMPOSTOR_SIZE:
			var u: float = float(x) / IMPOSTOR_SIZE - 0.5
			var v: float = 1.0 - float(y) / IMPOSTOR_SIZE
			var crown: float = Vector2(u * 1.6, (v - 0.6) * 1.3).length() + noise.get_noise_2d(x, y) * 0.12
			var trunk: bool = absf(u) < 0.035 and v < 0.35
			if crown < 0.42:
				image.set_pixel(x, y, Color(0.16, 0.3, 0.1).lightened(noise.get_noise_2d(x * 2, y * 2) * 0.2))
			elif trunk:
				image.set_pixel(x, y, Color(0.3, 0.22, 0.14))
	return image
