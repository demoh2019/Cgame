extends Node3D
## The visual side of one world chunk: its terrain and every tree, rock, bush and crate in it.
## Nothing here is sent over the network. It is built from the seed, and only the "depleted" and
## "opened" flags from the server change what is shown.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Dungeon = preload("res://scripts/shared/dungeon.gd")
const Meshes = preload("res://scripts/client/meshes.gd")
const Assets = preload("res://scripts/client/assets.gd")
const Foliage = preload("res://scripts/client/foliage.gd")
const CharacterModel = preload("res://scripts/client/character_model.gd")
const ModelCatalog = preload("res://scripts/client/model_catalog.gd")
const WorldRoads = preload("res://scripts/shared/world_roads.gd")
const GrassField = preload("res://scripts/client/grass_field.gd")
const GroundContactAO = preload("res://scripts/client/ground_contact_ao.gd")
const TerrainSeamNormals = preload("res://scripts/client/terrain_seam_normals.gd")
const TerrainAnisotropy = preload("res://scripts/client/terrain_anisotropy.gd")
const ObjectBatchGrid = preload("res://scripts/client/object_batch_grid.gd")
const SceneryBatches = preload("res://scripts/client/scenery_batches.gd")
const ShadowBudget = preload("res://scripts/client/shadow_budget.gd")
const DungeonLightBudget = preload("res://scripts/client/dungeon_light_budget.gd")
const DungeonReflectionBudget = preload("res://scripts/client/dungeon_reflection_budget.gd")
const DungeonOcclusion = preload("res://scripts/client/dungeon_occlusion.gd")
const SceneryLod = preload("res://scripts/client/scenery_lod.gd")

const SAMPLES := 33 # Heights per side: one every 2 m.
const HEIGHT_MIN := -45.0
const HEIGHT_RANGE := 220.0
const GROUND_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
global uniform float aa_weather_wetness;
global uniform float aa_weather_rain;
global uniform float aa_puddle_ripple_strength;
global uniform float aa_ground_contact_strength;
global uniform float aa_terrain_detail_radius;
instance uniform float aa_lod_morph = 0.0;
#include "res://assets/shaders/cloud_shadow.gdshaderinc"
#include "res://assets/shaders/puddle_ripples.gdshaderinc"
#include "res://assets/shaders/water_caustics.gdshaderinc"

// A painted-looking ground: smooth patches of lush and dry grass, dirt, sand at the shore, strata on slopes and
// snow on the peaks, all from layered value noise so nothing repeats in a visible grid.
varying vec3 world_position;
varying vec3 world_normal;
varying float vertex_cloud_shade;
// Roads of this chunk: a 1 m per pixel mask of the chunk (white = road). Chunks without roads keep the black default.
uniform sampler2D road_mask : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D contact_map : hint_default_white, filter_linear, repeat_disable;
uniform vec2 chunk_origin = vec2(0.0);
uniform float chunk_size = 64.0;

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
	VERTEX.y = mix(VERTEX.y, UV2.x, aa_lod_morph * UV2.y);
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Macro shadows change slowly in world space: evaluating them per vertex avoids
	// three noise passes per terrain pixel on OpenGL Compatibility.
	vertex_cloud_shade = cloud_shadow(world_position.xz, TIME);
}

void fragment() {
	vec2 p = world_position.xz;
	float h = world_position.y;
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float broad = fbm(p * 0.012);
	float mid = fbm(p * 0.09 + 3.0);
	// High-frequency noise is subpixel at a distance. Match textured terrain's
	// detail radius, fade gently, and skip both noise evaluations far away.
	float distance_to_camera = distance(p, CAMERA_POSITION_WORLD.xz);
	float detail_fade = 1.0 - smoothstep(aa_terrain_detail_radius,
			aa_terrain_detail_radius + 24.0, distance_to_camera);
	float fine = 0.5;
	float speck = 0.5;
	if (detail_fade > 0.001) {
		fine = mix(0.5, value_noise(p * 3.1), detail_fade);
		speck = mix(0.5, value_noise(p * 11.0), detail_fade);
	}

	vec3 lush = vec3(0.14, 0.34, 0.1);
	vec3 dry = vec3(0.4, 0.42, 0.18);
	vec3 meadow = mix(lush, dry, smoothstep(0.35, 0.7, broad));
	meadow *= 0.78 + 0.5 * mid;
	meadow = mix(meadow, meadow * vec3(1.15, 1.1, 0.75), smoothstep(0.65, 0.9, speck) * 0.5);
	meadow *= 0.93 + 0.14 * fine;
	vec3 dirt = vec3(0.34, 0.25, 0.16) * (0.8 + 0.4 * mid);
	vec3 sand = vec3(0.62, 0.55, 0.38) * (0.92 + 0.12 * fine);
	vec3 rock = vec3(0.45, 0.42, 0.4);
	// Coarse strata remain visible in the distance; four fine noise octaves are
	// only evaluated near the player. This preserves mountain silhouette.
	float strata = mid;
	if (detail_fade > 0.001) {
		strata = mix(mid, fbm(vec2(p.x * 0.18 + p.y * 0.14, h * 1.6)), detail_fade);
	}
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

	// Packed dirt roads with pebbles and a worn, darker middle.
	float road = textureLod(road_mask, (p - chunk_origin) / chunk_size, 0.0).r;
	if (road > 0.01) {
		vec3 dirt_road = vec3(0.44, 0.35, 0.24) * (0.82 + 0.3 * mid) * (0.9 + 0.2 * fine);
		dirt_road = mix(dirt_road, vec3(0.6, 0.56, 0.5), smoothstep(0.78, 0.95, speck) * 0.6);
		dirt_road *= 1.0 - 0.12 * smoothstep(0.75, 1.0, road);
		color = mix(color, dirt_road, smoothstep(0.08, 0.55, road));
	}

	// Dirt darkens during rain; thin puddles gather on level roads without extra samples.
	float wetness = clamp(aa_weather_wetness, 0.0, 1.0);
	float wettable = max(road, 0.35 * (1.0 - smoothstep(0.08, 0.55, slope)));
	float puddle = wetness * wettable * smoothstep(0.54, 0.77, mid)
		* (1.0 - smoothstep(0.08, 0.25, slope));
	color *= 1.0 - wetness * 0.12 - puddle * 0.13;
	// Shared moving cloud cover, interpolated across terrain vertices for low GPU cost.
	// Contact AO remains visible without downloaded terrain textures or SSAO.
	float ground_contact = 1.0;
	if (aa_ground_contact_strength > 0.001 && detail_fade > 0.001) {
		float contact_sample = texture(contact_map,
			clamp((p - chunk_origin) / chunk_size, vec2(0.0), vec2(1.0))).r;
		ground_contact = 1.0 - (1.0 - contact_sample)
			* aa_ground_contact_strength * detail_fade;
	}
	AO = ground_contact;
	ALBEDO = color * mix(1.0, ground_contact, 0.12)
		* mix(vec3(1.0), vec3(0.58, 0.63, 0.74), vertex_cloud_shade);
	// Match the same water caustic field even if 13-layer PBR assets are absent.
	// Low-end graphics uniformly skip the shader math on Compatibility.
	float caustics = aa_water_caustic_illumination(
		p, h, world_normal.y, distance_to_camera, TIME);
	ALBEDO += vec3(0.10, 0.19, 0.18) * caustics
		* (1.0 - vertex_cloud_shade * 0.70);
	float dry_roughness = mix(0.95, 0.75, shore);
	// Reuse the near-camera fine noise for subtle dry soil roughness variation;
	// no extra texture samples, and wet puddles stay glossy.
	ROUGHNESS = clamp(mix(mix(dry_roughness + (fine - 0.5) * 0.12 * detail_fade, 0.24, wetness * 0.35),
			0.08, puddle * 0.65), 0.08, 1.0);
	SPECULAR = min(0.9, 0.15 + wetness * 0.12 + puddle * 0.3);
	// Even without downloaded terrain textures, puddles have the same
	// coherent near-field rain rings. NORMAL is view-space in fragment().
	if (aa_puddle_ripple_strength > 0.001 && aa_weather_rain > 0.005 && puddle > 0.05
			&& distance_to_camera < aa_terrain_detail_radius) {
		float ripple_fade = 1.0 - smoothstep(
			aa_terrain_detail_radius * 0.58, aa_terrain_detail_radius,
			distance_to_camera);
		vec2 ripple_tilt = aa_puddle_ripple_tilt(p, TIME);
		vec3 view_tilt = (VIEW_MATRIX *
			vec4(ripple_tilt.x, 0.0, ripple_tilt.y, 0.0)).xyz;
		NORMAL = normalize(NORMAL + view_tilt
			* (aa_weather_rain * aa_puddle_ripple_strength * sqrt(puddle) * ripple_fade));
	}
}
"""

static var _ground_material: ShaderMaterial
static var _textured_material: ShaderMaterial
static var _textured_checked := false
static var terrain_filter_quality := 1
static var terrain_geomorph_enabled := false
static var terrain_max_lod_pixel_error := 0.0
static var terrain_screen_lod_quality := 1
const TERRAIN_LOD_GROUP := "aa_chunked_terrain_lod"
const TERRAIN_LAYERS := ["lush", "dry", "forest", "swamp", "road", "cliff", "mountain", "sand", "snow", "asphalt", "concrete", "brick", "plank"]
const TERRAIN_DIR := "res://assets/textures/terrain/"
# The colour each layer should average to: photos of real ground pulled toward the stylised palette of the models.
const TERRAIN_TARGETS := [Color(0.24, 0.38, 0.14), Color(0.37, 0.41, 0.19), Color(0.28, 0.32, 0.15), Color(0.27, 0.29, 0.17),
	Color(0.4, 0.38, 0.26), Color(0.36, 0.39, 0.29), Color(0.37, 0.41, 0.28), Color(0.66, 0.59, 0.44), Color(0.92, 0.94, 0.98),
	Color(0.3, 0.3, 0.29), Color(0.35, 0.37, 0.3), Color(0.43, 0.32, 0.27), Color(0.35, 0.31, 0.24)]
# Paved ground under sites (see ground.gdshader): kind -> [terrain layer, share of the site radius].
const SITE_PAVING := {"city": [11, 0.8], "bunker": [10, 0.75], "depot": [10, 0.6], "dock": [12, 0.65]}
const BIOME_TEXELS := 17 # Biome samples per chunk side (every 4 m), shared on the borders with the neighbours.

var cell: Vector2i
# Kept from building the terrain for the grass: raw heights, biome names, the road mask and the paved sites.
var _raw_heights := PackedFloat32Array()
var _biome_names := PackedStringArray()
var _road_data := PackedByteArray()
var _patches := PackedVector4Array()
# Grass grows tile by tile once the chunk is near the camera, within a time budget per frame across all chunks.
var _grass_source
var _grass_next_tile := 0
var _grass_tiles: Array[MultiMeshInstance3D] = []
var _grass_lod_elapsed := 0.0
var _grass_last_eye := Vector2.ZERO
var _grass_last_scale := -1.0
var _grass_last_tile_count := -1
var _grass_last_camera_y := INF
var _grass_last_camera_forward := Vector3.ZERO
const GRASS_LOD_INTERVAL := 0.35 # Update a few times a second, not every render frame.
var _shadow_casters: Array[Dictionary] = [] # Instanced geometry with true bounds and visual role.
# All shadows are static until a quality change or streamed caster changes.
# Store the last actual scan, not the last interval tick.
var _shadow_last_eye := Vector2.INF
var _shadow_last_revision := -1
var _shadow_last_count := -1
var _shadow_timer := 0.0
const SHADOW_INTERVAL := 0.5
static var _grass_frame := -1
static var _grass_spent_usec := 0
## Runtime tuning keeps the grass LOD system intact while bounding draw distance and generation spikes.
const GRASS_GROUP := "aa_grass_tiles"
const TERRAIN_GROUP := "aa_textured_terrain"
const SCENERY_GROUP := "aa_scenery_multimeshes"
static var scenery_quality := 1
static var grass_budget_usec := 2500
static var grass_range := 110.0
static var grass_visibility_end := 82.0
static var grass_fade_end := GrassField.FADE_END


## Sampler quality follows the existing graphics preset without changing any
## world or texture data. New chunks use the cached shader of the chosen tier.
static func configure_terrain_geomorph(quality: int) -> void:
	var tier: int = clampi(quality, 0, 3)
	terrain_geomorph_enabled = tier >= 2
	terrain_max_lod_pixel_error = [0.0, 0.0, 3.0, 1.5][tier]


static func apply_terrain_geomorph(node: Node) -> void:
	if node is ChunkedTerrain3D:
		var terrain := node as ChunkedTerrain3D
		terrain.lod_geomorph_enabled = terrain_geomorph_enabled
		terrain.max_lod_pixel_error = terrain_max_lod_pixel_error
		# A slightly faster update preserves smooth movement while the native
		# engine changes only one per-instance uniform, never reuploads meshes.
		terrain.update_interval = 0.16 if terrain_geomorph_enabled else 0.5


## Screen-relative geometry thresholds for the forked ChunkedTerrain3D.
## Existing and new terrain chunks use the same quality-selected budget.
static func terrain_lod_distance_for_quality(quality: int) -> float:
	return [55.0, 70.0, 90.0, 112.0][clampi(quality, 0, 3)]


static func configure_terrain_screen_lod(quality: int) -> void:
	terrain_screen_lod_quality = clampi(quality, 0, 3)


static func apply_terrain_screen_lod(node: Node) -> void:
	if node is ChunkedTerrain3D:
		var terrain := node as ChunkedTerrain3D
		terrain.screen_space_lod_enabled = true
		terrain.lod_reference_fov = 38.0 # Matches the 720p gameplay camera.
		terrain.lod_distance = terrain_lod_distance_for_quality(terrain_screen_lod_quality)


static func configure_terrain_filter(quality: int) -> void:
	terrain_filter_quality = clampi(quality, 0, 3)
	if _textured_material != null:
		TerrainAnisotropy.apply(_textured_material, terrain_filter_quality)


## Existing chunks keep their road/biome maps and material parameter overrides.
static func apply_terrain_filter(terrain: Node) -> void:
	if terrain == null or not terrain.is_in_group(TERRAIN_GROUP):
		return
	var shader_material: ShaderMaterial = terrain.get("material") as ShaderMaterial
	if shader_material != null:
		TerrainAnisotropy.apply(shader_material, terrain_filter_quality)


static func configure_grass(build_radius: float, budget_usec: int, fade_start: float, fade_end: float) -> void:
	grass_range = build_radius
	grass_budget_usec = budget_usec
	grass_visibility_end = fade_end + 22.0
	grass_fade_end = fade_end
	var material: ShaderMaterial = GrassField.material()
	material.set_shader_parameter("fade_start", fade_start)
	material.set_shader_parameter("fade_end", fade_end)
## Streamed instances inherit user quality; existing instances change only
## when the preset changes, not each frame.
static func configure_scenery(quality: int) -> void:
	scenery_quality = clampi(quality, 0, 3)


static func apply_scenery_detail(instance: MultiMeshInstance3D) -> void:
	if instance == null or not instance.has_meta("aa_scenery_kind"):
		return
	SceneryLod.apply(instance, str(instance.get_meta("aa_scenery_kind")),
		scenery_quality, float(instance.get_meta("aa_scenery_distance", 0.0)))


static func register_scenery(instance: MultiMeshInstance3D, kind: String,
		base_distance: float = 0.0) -> void:
	instance.set_meta("aa_scenery_kind", kind)
	instance.set_meta("aa_scenery_distance", base_distance)
	instance.add_to_group(SCENERY_GROUP)
	apply_scenery_detail(instance)


var _world
var _terrain
var _groups: Dictionary = {} # kind -> {"multimesh": MultiMesh, "index": {node_id: i}, "transforms": [...]}
var _hidden: Dictionary = {} # node id -> true, currently hidden
var _contact_nodes: Array = []
var _contact_structures: Array = []
var _contact_material_private := false
var _use_nature := false
var _use_village := false


static func ground_material() -> ShaderMaterial:
	if _ground_material == null:
		var shader := Shader.new()
		shader.code = GROUND_SHADER
		_ground_material = ShaderMaterial.new()
		_ground_material.shader = shader
	return _ground_material


## The textured ground material (Poly Haven layers in two texture arrays), or null when the textures are missing.
static func textured_material() -> ShaderMaterial:
	if _textured_checked:
		return _textured_material
	_textured_checked = true
	var albedo: Array[Image] = []
	var normals: Array[Image] = []
	for layer in TERRAIN_LAYERS:
		var diffuse_texture := load(TERRAIN_DIR + layer + "_diff.jpg") as Texture2D
		var normal_texture := load(TERRAIN_DIR + layer + "_nor_gl.jpg") as Texture2D
		if diffuse_texture == null or normal_texture == null:
			return null
		albedo.append(_layer_image(diffuse_texture, 1024))
		normals.append(_layer_image(normal_texture, 512))
	var tints := PackedVector3Array()
	var averages := PackedVector3Array()
	for index in albedo.size():
		var small: Image = albedo[index].duplicate()
		small.clear_mipmaps()
		small.resize(16, 16, Image.INTERPOLATE_BILINEAR)
		var sum := Vector3.ZERO
		for y in 16:
			for x in 16:
				var pixel: Color = small.get_pixel(x, y)
				sum += Vector3(pixel.r, pixel.g, pixel.b)
		var average: Vector3 = sum / 256.0
		var target: Color = TERRAIN_TARGETS[index]
		averages.append(Vector3(target.r, target.g, target.b))
		tints.append(Vector3(target.r / maxf(average.x, 0.02), target.g / maxf(average.y, 0.02), target.b / maxf(average.z, 0.02)))
	var albedo_array := Texture2DArray.new()
	var normal_array := Texture2DArray.new()
	if albedo_array.create_from_images(albedo) != OK or normal_array.create_from_images(normals) != OK:
		return null
	var shader: Shader = TerrainAnisotropy.shader_for_quality(terrain_filter_quality)
	if shader == null:
		return null
	_textured_material = ShaderMaterial.new()
	_textured_material.shader = shader
	_textured_material.set_shader_parameter("albedo_layers", albedo_array)
	_textured_material.set_shader_parameter("normal_layers", normal_array)
	_textured_material.set_shader_parameter("biome_texels", float(BIOME_TEXELS))
	_textured_material.set_shader_parameter("layer_tint", tints)
	_textured_material.set_shader_parameter("layer_average", averages)
	return _textured_material


## An imported texture as a plain RGB image of a fixed size with mipmaps, so all layers of an array match.
static func _layer_image(texture: Texture2D, size: int) -> Image:
	var image: Image = texture.get_image()
	if image.is_compressed():
		image.decompress()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGB8)
	if image.get_width() != size or image.get_height() != size:
		image.resize(size, size, Image.INTERPOLATE_LANCZOS)
	image.generate_mipmaps()
	return image


## Up to four paved sites that reach into this chunk, as x, z, radius, layer for the ground shader.
func _site_patches(origin: Vector2) -> PackedVector4Array:
	var patches := PackedVector4Array()
	var center := origin + Vector2.ONE * Defs.CHUNK_SIZE * 0.5
	for site in _world.poi.sites_near(center.x, center.y, Defs.CHUNK_SIZE * 0.75):
		if patches.size() >= 4 or not SITE_PAVING.has(site["kind"]):
			continue
		var paving: Array = SITE_PAVING[site["kind"]]
		patches.append(Vector4(float(site["x"]), float(site["z"]), float(site["radius"]) * float(paving[1]), float(paving[0])))
	while patches.size() < 4:
		patches.append(Vector4.ZERO)
	return patches


## Forest, swamp and plains weights of the chunk, one texel every 4 m, edges shared with the neighbouring chunks.
func _biome_texture(origin: Vector2) -> ImageTexture:
	var data := PackedByteArray()
	data.resize(BIOME_TEXELS * BIOME_TEXELS * 3)
	var step: float = Defs.CHUNK_SIZE / float(BIOME_TEXELS - 1)
	for j in BIOME_TEXELS:
		for i in BIOME_TEXELS:
			var biome: String = _world.biome_at(origin.x + float(i) * step, origin.y + float(j) * step)
			_biome_names.append(biome)
			var index: int = (j * BIOME_TEXELS + i) * 3
			data[index] = 255 if biome == "forest" else 0
			data[index + 1] = 255 if biome == "swamp" else 0
			data[index + 2] = 255 if biome == "plains" else 0
	return ImageTexture.create_from_image(Image.create_from_data(BIOME_TEXELS, BIOME_TEXELS, false, Image.FORMAT_RGB8, data))


## The ground material of this chunk: the textured one with this chunk's biome map and road mask, or the painted shader
## (with the road mask when roads cross it) when the terrain textures are missing.
func _ground_with_roads(origin: Vector2) -> Material:
	var textured: ShaderMaterial = textured_material()
	var road_texture: ImageTexture = _road_texture(origin)
	if textured != null:
		var own := textured.duplicate() as ShaderMaterial
		own.set_shader_parameter("biome_map", _biome_texture(origin))
		if road_texture != null:
			own.set_shader_parameter("road_mask", road_texture)
		own.set_shader_parameter("chunk_origin", origin)
		own.set_shader_parameter("chunk_size", Defs.CHUNK_SIZE)
		_patches = _site_patches(origin)
		own.set_shader_parameter("site_patches", _patches)
		return own
	if road_texture == null:
		return ground_material()
	var material := ground_material().duplicate() as ShaderMaterial
	material.set_shader_parameter("road_mask", road_texture)
	material.set_shader_parameter("chunk_origin", origin)
	material.set_shader_parameter("chunk_size", Defs.CHUNK_SIZE)
	return material


## The roads crossing this chunk as a 1 m per pixel mask, or null when none does.
func _road_texture(origin: Vector2) -> ImageTexture:
	if _world.roads == null:
		return null
	var pieces: Array = _world.roads.pieces_in_cell(cell)
	if pieces.is_empty():
		return null
	var size: int = int(Defs.CHUNK_SIZE)
	var data := PackedByteArray()
	data.resize(size * size)
	var half: float = WorldRoads.HALF_WIDTH
	var soft: float = 1.2
	for piece in pieces:
		var a: Vector2 = piece[0] - origin
		var b: Vector2 = piece[1] - origin
		var reach: float = half + soft
		var x0: int = maxi(0, floori(minf(a.x, b.x) - reach))
		var x1: int = mini(size - 1, ceili(maxf(a.x, b.x) + reach))
		var y0: int = maxi(0, floori(minf(a.y, b.y) - reach))
		var y1: int = mini(size - 1, ceili(maxf(a.y, b.y) + reach))
		var ab: Vector2 = b - a
		var length_squared: float = maxf(ab.length_squared(), 0.0001)
		for py in range(y0, y1 + 1):
			for px in range(x0, x1 + 1):
				var point := Vector2(float(px) + 0.5, float(py) + 0.5)
				var t_along: float = clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
				var distance: float = point.distance_to(a + ab * t_along)
				if distance >= reach:
					continue
				var value: int = int(255.0 * clampf((reach - distance) / soft, 0.0, 1.0))
				var index: int = py * size + px
				if value > data[index]:
					data[index] = value
	_road_data = data
	return ImageTexture.create_from_image(Image.create_from_data(size, size, false, Image.FORMAT_L8, data))


func build(p_world, p_cell: Vector2i) -> void:
	_use_nature = Assets.has_nature()
	_use_village = Assets.has_village()
	_world = p_world
	cell = p_cell
	# Stagger 0.5-second shadow checks across neighboring chunks to avoid update spikes.
	_shadow_timer = float(posmod(cell.x * 37 + cell.y * 19, 50)) * 0.01
	var origin := WorldGen.cell_origin(cell)
	if Dungeon.is_underground(origin.x + Defs.CHUNK_SIZE):
		_build_dungeon(origin)
		_build_objects(_world.chunk(cell)) # The chests.
		return
	_build_terrain(origin)
	var data: Dictionary = _world.chunk(cell)
	_build_objects(data)


# --- Underground ------------------------------------------------------------------------------------------------------

static var _kit_scenes: Dictionary = {}


## A piece of the dungeon kit, scaled so its width is `width` metres, standing at `at` facing `yaw`.
func _kit(piece: String, at: Vector3, yaw: float, width: float = Dungeon.TILE, height_factor: float = 1.0) -> Node3D:
	if not _kit_scenes.has(piece):
		var path: String = Assets.PACKS + "dungeon/%s.gltf" % piece
		_kit_scenes[piece] = load(path) if ResourceLoader.exists(path) else null
	var scene := _kit_scenes[piece] as PackedScene
	if scene == null:
		return null
	var node := scene.instantiate() as Node3D
	var bounds := AABB()
	var first := true
	for found in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_box: AABB = (found as MeshInstance3D).get_aabb()
		bounds = mesh_box if first else bounds.merge(mesh_box)
		first = false
	var size: float = maxf(bounds.size.x, bounds.size.z)
	var factor: float = width / size if size > 0.01 else 1.0
	node.scale = Vector3(factor, factor * height_factor, factor)
	node.position = at - Vector3(_world_origin().x, 0, _world_origin().y)
	# `yaw` turns the piece's length along the wall; kit pieces that run along their own Z need a quarter turn more.
	node.rotation.y = yaw + (PI * 0.5 if bounds.size.z > bounds.size.x * 1.2 else 0.0)
	add_child(node)
	return node


## A chunk below ground: dark rock everywhere, and where the complex's rooms are, stone floors, low walls (the camera
## looks down over them), columns at the doorways and a torch in every room.
func _build_dungeon(origin: Vector2) -> void:
	var rock := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * Defs.CHUNK_SIZE
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.045, 0.04)
	dark.roughness = 1.0
	plane.material = dark
	rock.mesh = plane
	rock.position = Vector3(Defs.CHUNK_SIZE * 0.5, Dungeon.FLOOR_Y - 0.03, Defs.CHUNK_SIZE * 0.5)
	add_child(rock)
	var cell_rect := Rect2(origin, Vector2.ONE * Defs.CHUNK_SIZE)
	var region: Vector2i = Dungeon.region_of(origin.x + Defs.CHUNK_SIZE * 0.5, origin.y + Defs.CHUNK_SIZE * 0.5)
	if _world.dungeon_bunker(region).is_empty():
		return
	var layout: Dictionary = Dungeon.layout(_world.world_seed, region)
	for room in layout["rooms"]:
		var center: Vector2 = Dungeon.room_center(region, room)
		for i in Dungeon.ROOM_TILES:
			for j in Dungeon.ROOM_TILES:
				var tile: Vector2 = center + (Vector2(i, j) - Vector2.ONE * float(Dungeon.ROOM_TILES - 1) * 0.5) * Dungeon.TILE
				if cell_rect.has_point(tile):
					_kit("floor_tile_large" if (i + j + room.x) % 3 != 0 else "floor_tile_large_rocks", Vector3(tile.x, Dungeon.FLOOR_Y, tile.y), 0.0)
		if cell_rect.has_point(center):
			# A cheap marker for the shared room reflection pool; no per-room
			# cubemap is created until the player approaches on High/Ultra.
			var room_anchor := Node3D.new()
			room_anchor.name = "RoomReflectionAnchor"
			room_anchor.position = Vector3(center.x - origin.x,
				Dungeon.FLOOR_Y + 1.8, center.y - origin.y)
			room_anchor.add_to_group(DungeonReflectionBudget.GROUP)
			add_child(room_anchor)
			# A torch on the north wall lights the room.
			var torch_at := Vector3(center.x, Dungeon.FLOOR_Y, center.y - Dungeon.ROOM * 0.5 + 0.4)
			_kit("torch_mounted", torch_at + Vector3(0, 1.4, 0), 0.0, 0.5)
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.68, 0.36)
			light.light_energy = 2.2
			light.omni_range = 11.0
			light.shadow_enabled = false # Keep nearby torch lighting affordable on Compatibility.
			light.visible = false # Only the global camera-nearest light budget turns torches on.
			light.position = torch_at + Vector3(0, 2.2, 1.2) - Vector3(origin.x, 0, origin.y)
			light.set_meta("aa_flame_seed", float(room.x * 13 + room.y * 7))
			light.add_to_group(DungeonLightBudget.GROUP)
			add_child(light)
			if room == layout["boss"]:
				_kit("chest_gold", Vector3(center.x + 2.0, Dungeon.FLOOR_Y, center.y + 2.0), PI, 1.2)
	for piece in Dungeon.walls(_world.world_seed, region):
		var a: Vector2 = piece["a"]
		var b: Vector2 = piece["b"]
		var mid: Vector2 = (a + b) * 0.5
		if not cell_rect.has_point(mid):
			continue
		var yaw: float = atan2(-(b - a).y, (b - a).x)
		if piece["door"]:
			_kit("column", Vector3(a.x, Dungeon.FLOOR_Y, a.y), 0.0, 0.9)
			_kit("column", Vector3(b.x, Dungeon.FLOOR_Y, b.y), 0.0, 0.9)
		else:
			# The kit's 4 m wall, kept below head height so the camera looks over it into the next room.
			var wall_piece := _kit("wall", Vector3(mid.x, Dungeon.FLOOR_Y, mid.y), yaw, Dungeon.TILE, 0.45)
			# Only complete, opaque dungeon walls can hide other room geometry.
			# The conservative software-occluder sits inside the visible wall mesh.
			DungeonOcclusion.add_wall(wall_piece)


func _build_terrain(origin: Vector2) -> void:
	var heights := PackedFloat32Array()
	heights.resize(SAMPLES * SAMPLES)
	var step := Defs.CHUNK_SIZE / float(SAMPLES - 1)
	for j in SAMPLES:
		for i in SAMPLES:
			var h: float = _world.height_at(origin.x + i * step, origin.y + j * step)
			heights[j * SAMPLES + i] = clampf((h - HEIGHT_MIN) / HEIGHT_RANGE, 0.0, 1.0)
			_raw_heights.append(h)
	_terrain = ChunkedTerrain3D.new()
	_terrain.centered = false
	_terrain.size = Vector2(Defs.CHUNK_SIZE, Defs.CHUNK_SIZE)
	_terrain.height_scale = HEIGHT_RANGE
	_terrain.height_offset = HEIGHT_MIN
	_terrain.chunk_quads = 16
	_terrain.lod_count = 3
	_terrain.lod_distance = 70.0
	apply_terrain_screen_lod(_terrain)
	_terrain.lod_geomorph_enabled = terrain_geomorph_enabled
	_terrain.max_lod_pixel_error = terrain_max_lod_pixel_error
	_terrain.skirt_depth = 3.0
	_terrain.collision_enabled = false # The server decides where players can stand.
	_terrain.cast_shadows = false
	_terrain.update_interval = 0.16 if terrain_geomorph_enabled else 0.5
	_terrain.material = _ground_with_roads(origin)
	_terrain.set_height_data(heights, Vector2i(SAMPLES, SAMPLES))
	# The forked ChunkedTerrain3D accepts normals sampled one grid step past
	# the current chunk. Their shared world-space derivative removes bright
	# vertical lighting seams without an extra shader pass or texture.
	_terrain.set_normal_data(TerrainSeamNormals.build(_raw_heights, origin,
		SAMPLES, step, HEIGHT_MIN, HEIGHT_RANGE, Callable(_world, "height_at")))
	add_child(_terrain)
	_terrain.add_to_group(TERRAIN_LOD_GROUP)
	if _textured_material != null:
		_terrain.add_to_group(TERRAIN_GROUP)


# Trees by biome (nature kit file names; "painted:N" is a tree of the hand-painted collection).
const TREES_BY_BIOME := {
	"forest": ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5", "Pine_1", "Pine_2", "Pine_3", "painted:0", "painted:1", "painted:2", "painted:3", "painted:4"],
	"plains": ["CommonTree_1", "CommonTree_2", "CommonTree_4", "painted:5", "painted:6", "painted:7"],
	# Wet woodland, alive and overgrown: twisted alders and broad trees, a rare drowned snag for the mood.
	"swamp": ["TwistedTree_1", "TwistedTree_2", "TwistedTree_3", "TwistedTree_4", "TwistedTree_1", "TwistedTree_3", "CommonTree_3", "CommonTree_5", "painted:8", "painted:9", "DeadTree_1"],
	"mountain": ["Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5", "DeadTree_2"],
	"beach": ["CommonTree_2", "CommonTree_5", "Pine_4"],
}


## Which tree stands at a node: by biome, stable for the node id.
func _tree_key(node: Dictionary) -> String:
	var biome: String = _world.biome_at(float(node["x"]), float(node["z"]))
	var options: Array = TREES_BY_BIOME.get(biome, TREES_BY_BIOME["forest"])
	if not ModelCatalog.has_painted_trees():
		options = options.filter(func(name: String) -> bool: return not name.begins_with("painted"))
	return "tree:" + str(options[WorldGen.mix(int(node["id"]), 3, 5) % options.size()])


## Mesh of a group. Kinds with a number ("tree:3", "building:5") are variants; the catalog picks the model installed for it,
## and each branch falls back to the Kenney or procedural models when its packs are missing.
func _mesh_for(kind: String) -> Mesh:
	if _use_nature and kind.begins_with("tree:") and not kind.substr(5).is_valid_int():
		var tree_id: String = kind.substr(5)
		if tree_id.begins_with("painted:"):
			return Foliage.swayed(ModelCatalog.painted_tree(int(tree_id.get_slice(":", 1))), "painted:" + tree_id, 0.2)
		return Foliage.swayed(Assets.nature_mesh(tree_id), "tree:" + tree_id, 0.08 if tree_id.begins_with("DeadTree") else 0.2)
	if kind.begins_with("monument:"):
		var monument: Mesh = ModelCatalog.monument(int(kind.get_slice(":", 1)))
		if monument != null:
			return Foliage.swayed(monument, "monument:" + kind, 0.35) if kind == "monument:2" else monument
		return Assets.building_mesh(4)
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
				var original_count: int = Assets.tree_meshes().size()
				if variant >= original_count:
					var tree_entry: Dictionary = ModelCatalog.BUILTIN_TREES[(variant - original_count) % ModelCatalog.BUILTIN_TREES.size()]
					var extended_tree: Mesh = ModelCatalog.entry_mesh(tree_entry)
					if extended_tree != null:
						return Foliage.swayed(extended_tree, "kenney_expanded_tree:%d" % variant, 0.18)
				return Assets.tree_meshes()[variant % original_count]
		"rock":
			if ModelCatalog.has_scanned_rocks():
				picked = ModelCatalog.scanned_rock(variant)
				if picked != null:
					return picked
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
	if kind.begins_with("tree:TwistedTree"):
		return rng.randf_range(0.45, 0.6)
	if kind.begins_with("monument:"):
		return 1.0 if ModelCatalog.monument(int(kind.get_slice(":", 1))) != null else 3.0
	match base:
		"tree":
			if _use_nature:
				# Mostly mature trees, a few saplings and now and then an old giant that towers over the canopy: the
				# height range is what gives a wood its silhouette.
				var age: float = rng.randf()
				if age < 0.1:
					return rng.randf_range(1.55, 1.95)
				if age < 0.25:
					return rng.randf_range(0.6, 0.8)
				return rng.randf_range(0.9, 1.3)
			if variant >= Assets.tree_meshes().size():
				return rng.randf_range(0.75, 1.25) # The expanded kit is already fitted to metre-scale trees.
			return Assets.TREE_SCALE * rng.randf_range(0.85, 1.3)
		"rock":
			if ModelCatalog.has_scanned_rocks():
				return rng.randf_range(0.75, 1.15)
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
	# The procedural contact mask is baked once from existing world objects.
	# It lives on the terrain material; no new mesh or shadow caster is spawned.
	if _terrain != null:
		_contact_nodes = data.get("nodes", [])
		_contact_structures = data.get("structures", [])
		_refresh_ground_contact()
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldGen.mix(cell.x, cell.y, 99)
	var tree_variants: int = Assets.tree_meshes().size() + ModelCatalog.BUILTIN_TREES.size()
	if _use_nature:
		tree_variants = Assets.TREE_FILES.size() + (ModelCatalog.PAINTED_TREES.size() if ModelCatalog.has_painted_trees() else 0)
	var rock_variants: int = Assets.ROCK_FILES.size() + (ModelCatalog.STONES.size() if ModelCatalog.has_stones() else 0)
	if ModelCatalog.has_scanned_rocks():
		rock_variants = ModelCatalog.SCANNED_ROCKS.size()
	var crystal_count: int = ModelCatalog.available("crystals", ModelCatalog.CRYSTALS).size()
	# Group everything that shares a mesh, so each group is one draw call.
	var by_kind: Dictionary = {}
	for node in data["nodes"]:
		var kind: String = node["kind"]
		var variant: int = WorldGen.mix(int(node["id"]), 3, 5)
		if kind == "tree":
			kind = _tree_key(node) if _use_nature else "tree:%d" % (variant % tree_variants)
		elif kind == "rock" and (_use_nature or rock_variants > Assets.ROCK_FILES.size() or ModelCatalog.has_scanned_rocks()):
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
	# Split repeated foliage into smaller visibility/LOD AABBs instead of treating
	# every tree of a kind across 64 metres as one inseparable GPU instance group.
	var batches: Dictionary = ObjectBatchGrid.partition(by_kind, origin, Defs.CHUNK_SIZE)
	for batch_id in batches:
		var batch: Dictionary = batches[batch_id]
		var kind: String = batch["kind"]
		var list: Array = batch["nodes"]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = _mesh_for(kind)
		multimesh.instance_count = list.size()
		var index: Dictionary = {}
		var transforms: Array = []
		var is_building: bool = kind.begins_with("wall") or kind.begins_with("building:") or kind.begins_with("tower") or kind == "workbench" or kind.begins_with("ruin:") or kind.begins_with("monument:")
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
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (kind.begins_with("tree:") or kind.begins_with("building:") or kind.begins_with("wall") or kind.begins_with("tower") or kind.begins_with("ruin:") or kind.begins_with("monument:")) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _use_nature and kind.begins_with("ore:") and crystal_count == 0:
			instance.material_override = _ore_material(multimesh.mesh)
		register_scenery(instance, kind)
		add_child(instance)
		if instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and multimesh.mesh != null:
			# The nearest tree in a MultiMesh group matters more than the chunk centre.
			_shadow_casters.append({"node": instance, "role": "tree" if kind.begins_with("tree:") else "structure",
				"bounds": SceneryBatches.bounds_for(multimesh.mesh, transforms)})
		_groups[batch_id] = {"multimesh": multimesh, "index": index, "transforms": transforms}
	_build_decor(origin, rng, data)
	_build_windmills(windmills, origin)
	_build_signposts(origin)
	_build_npcs(data.get("npcs", []))


## Wooden signposts beside the roads, naming the place at the other end and how far it is.
func _build_signposts(origin: Vector2) -> void:
	if _world.roads == null:
		return
	for sign in _world.roads.signs_in_cell(cell):
		var root := Node3D.new()
		var ground: float = _world.height_at(float(sign["x"]), float(sign["z"]))
		root.position = Vector3(float(sign["x"]) - origin.x, ground, float(sign["z"]) - origin.y)
		root.rotation.y = float(sign["yaw"])
		add_child(root)
		var pole := MeshInstance3D.new()
		pole.mesh = _signpost_pole()
		pole.position.y = 1.3
		root.add_child(pole)
		var board := MeshInstance3D.new()
		board.mesh = _signpost_board()
		board.position = Vector3(0.0, 2.25, 0.45) # The arrow end points along the road.
		root.add_child(board)
		var label := Label3D.new()
		label.text = "%s\n%d m" % [sign["to"], int(sign["metres"])]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 26
		label.pixel_size = 0.007
		label.outline_size = 8
		label.modulate = Color(1.0, 0.93, 0.75)
		label.position = Vector3(0.0, 3.0, 0.0)
		label.visibility_range_end = 34.0
		root.add_child(label)


static var _pole_mesh: Mesh
static var _board_mesh: Mesh


static func _wood_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.3, 0.17)
	material.roughness = 0.95
	return material


static func _signpost_pole() -> Mesh:
	if _pole_mesh == null:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.07
		cylinder.bottom_radius = 0.09
		cylinder.height = 2.6
		cylinder.radial_segments = 6
		cylinder.material = _wood_material()
		_pole_mesh = cylinder
	return _pole_mesh


static func _signpost_board() -> Mesh:
	if _board_mesh == null:
		var box := BoxMesh.new()
		box.size = Vector3(0.08, 0.34, 1.3)
		box.material = _wood_material()
		_board_mesh = box
	return _board_mesh


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
	_grow_grass()
	_grass_lod_elapsed += delta
	if _grass_lod_elapsed >= GRASS_LOD_INTERVAL:
		_grass_lod_elapsed = 0.0
		_update_grass_lods()
	_shadow_timer += delta
	if _shadow_timer >= SHADOW_INTERVAL:
		_shadow_timer = 0.0
		_update_shadow_casters()
	for sail in _sails:
		(sail["node"] as Node3D).rotate_object_local(sail["axis"], sail["speed"] * delta)


func _grow_grass() -> void:
	if _grass_source == null or _grass_next_tile >= GrassField.tile_count():
		return
	var frame: int = Engine.get_process_frames()
	if _grass_frame != frame:
		_grass_frame = frame
		_grass_spent_usec = 0
	if _grass_spent_usec > grass_budget_usec:
		return # This frame's share of grass growing is used up; the rest comes next frame.
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var center := global_position + Vector3(Defs.CHUNK_SIZE * 0.5, 0.0, Defs.CHUNK_SIZE * 0.5)
	if Vector2(camera.global_position.x - center.x, camera.global_position.z - center.z).length() > grass_range:
		return
	while _grass_next_tile < GrassField.tile_count() and _grass_spent_usec <= grass_budget_usec:
		var started := Time.get_ticks_usec()
		var tile: MultiMeshInstance3D = GrassField.build_tile(_grass_source, _grass_next_tile)
		_grass_next_tile += 1
		if tile != null:
			tile.visibility_range_end = grass_visibility_end
			add_child(tile)
			tile.add_to_group(GRASS_GROUP)
			_grass_tiles.append(tile)
		_grass_spent_usec += Time.get_ticks_usec() - started


## Keep silhouettes while trimming shadow-map rasterization. Updates are limited to
## twice a second and use the true world-space batch bounds (including group edges).
func _update_shadow_casters() -> void:
	if _shadow_casters.is_empty():
		return
	var view_camera: Camera3D = get_viewport().get_camera_3d()
	if view_camera == null:
		return
	var eye: Vector3 = view_camera.global_position
	var eye_xz := Vector2(eye.x, eye.z)
	if not ShadowBudget.needs_refresh(_shadow_last_eye, _shadow_last_revision,
			_shadow_last_count, eye_xz, _shadow_casters.size()):
		return
	_shadow_last_eye = eye_xz
	_shadow_last_revision = ShadowBudget.revision()
	_shadow_last_count = _shadow_casters.size()
	for entry in _shadow_casters:
		var caster: MultiMeshInstance3D = entry["node"]
		if not is_instance_valid(caster):
			continue
		var local_bounds: AABB = entry["bounds"]
		var world_bounds: AABB = caster.global_transform * local_bounds
		var distance: float = ShadowBudget.distance_to_bounds_xz(eye, world_bounds)
		var active: bool = caster.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var desired: bool = ShadowBudget.should_cast(str(entry["role"]), distance, active)
		if desired != active:
			caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if desired else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Three cached grass meshes (18 / 9 / 4 blades) keep detailed nearby grass.
## The tile buffer is shuffled once, so drawing fewer distant instances does not
## cut holes into one side of a tile. Changing visible count does not rebuild meshes.
func _update_grass_lods() -> void:
	if _grass_tiles.is_empty():
		return
	var view_camera := get_viewport().get_camera_3d()
	if view_camera == null:
		return
	var camera_xz := Vector2(view_camera.global_position.x, view_camera.global_position.z)
	# Compute one focal-length ratio for the whole chunk, not for each tuft.
	# Changing Ultra/Performance now changes real distant detail, not just
	# the shader's sink-to-ground fade range.
	var active_viewport: Viewport = view_camera.get_viewport()
	var screen_size: Vector2 = active_viewport.get_visible_rect().size
	var vertical_fov: float = view_camera.fov
	if view_camera.keep_aspect == Camera3D.KEEP_WIDTH and screen_size.x > 0:
		# KEEP_WIDTH expresses horizontal FOV. Convert it before computing
		# projected blade size, otherwise ultrawide screens choose wrong LODs.
		vertical_fov = rad_to_deg(2.0 * atan(
			tan(deg_to_rad(view_camera.fov) * 0.5) * float(screen_size.y) / float(screen_size.x)))
	var render_scale := 1.0
	if str(RenderingServer.get_current_rendering_method()) != "gl_compatibility":
		# FSR2 renders fewer 3D pixels than the window contains.
		render_scale = clampf(active_viewport.scaling_3d_scale, 0.5, 1.0)
	var screen_height: float = float(screen_size.y) * render_scale
	# The fork's native projection query handles perspective, frustum and
	# orthographic zoom, including tilted terrain and elevated grass.
	# Upstream Godot retains the original FOV-based approximation.
	var native_projection: bool = view_camera.has_method("get_pixels_per_meter_at_position")
	var screen_scale: float = minf(1.15, GrassField.screen_lod_scale(screen_height, vertical_fov))
	var raw_focal_ratio: float = (screen_height / tan(deg_to_rad(vertical_fov) * 0.5)) / (
		720.0 / tan(deg_to_rad(38.0) * 0.5))
	var quality_range: float = maxf(grass_fade_end / GrassField.FADE_END, 0.1)
	# Native pixels-per-meter already accounts for resolution and FOV, while
	# the fallback needs the old focal-length multiplier.
	var range_scale: float = quality_range if native_projection else quality_range * screen_scale
	var refresh_signature: float = quality_range * raw_focal_ratio
	if view_camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		refresh_signature = quality_range * (720.0 / maxf(view_camera.size, 0.01))
	var camera_forward: Vector3 = -view_camera.global_transform.basis.z
	var orientation_changed: bool = camera_forward.distance_squared_to(
		_grass_last_camera_forward) > 0.0001
	var height_changed: bool = absf(view_camera.global_position.y - _grass_last_camera_y) > 0.1
	if not GrassField.needs_lod_refresh(_grass_last_eye, _grass_last_scale,
			_grass_last_tile_count, camera_xz, refresh_signature, _grass_tiles.size()) \
			and not orientation_changed and not height_changed:
		return
	_grass_last_eye = camera_xz
	_grass_last_scale = refresh_signature
	_grass_last_tile_count = _grass_tiles.size()
	_grass_last_camera_y = view_camera.global_position.y
	_grass_last_camera_forward = camera_forward
	for tile in _grass_tiles:
		var tile_center: Vector3 = to_global(tile.custom_aabb.position + tile.custom_aabb.size * 0.5)
		var distance: float = camera_xz.distance_to(Vector2(tile_center.x, tile_center.z))
		if native_projection:
			var pixels_per_meter: float = float(view_camera.call(
				"get_pixels_per_meter_at_position", tile_center)) * render_scale
			distance = GrassField.projected_lod_distance(
				distance, pixels_per_meter, raw_focal_ratio)
		var previous: int = int(tile.get_meta("blade_lod", 0))
		var tier: int = GrassField.lod_for_distance(distance, previous, range_scale)
		# MultiMesh.visible_instance_count is a GPU draw limit; changing this
		# does not upload transforms or spawn new nodes every frame.
		var draw_count: int = GrassField.visible_count_for_distance(
			tile.multimesh.instance_count, distance, range_scale)
		if tile.multimesh.visible_instance_count != draw_count:
			tile.multimesh.visible_instance_count = draw_count
		if tier != previous:
			tile.multimesh.mesh = GrassField.clump_mesh(GrassField.LOD_BLADES[tier])
			tile.set_meta("blade_lod", tier)


## The people of the settlements: standing, sitting, working, each with a name and a role above their head.
func _build_npcs(npcs: Array) -> void:
	for npc in npcs:
		var model := CharacterModel.new()
		add_child(model)
		model.setup(Color.WHITE, 2.0, 1.0, str(npc["model"]) if Assets.has_characters() else "", false, hash(str(npc["name"]) + str(npc["role"])))
		model.position = Vector3(float(npc["x"]), float(npc["y"]), float(npc["z"])) - Vector3(_world_origin().x, 0.0, _world_origin().y)
		model.rotation.y = float(npc["yaw"])
		model.play_fixed(str(npc["animation"]))
		if str(npc["role"]) == "guard":
			model.set_weapon("spear_1") # Settlement guards stand armed.
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
# Every piece has a place it belongs to, as in a real landscape and as environment artists compose one (detail
# gathered in zones, calm open ground between them, roughly 70/30), instead of an even sprinkle that reads as noise:
#   "tree":   around tree trunks (ferns, mushrooms, bushes, the forest floor's branches, bark and roots);
#   "rock":   around rocks and ore (scree, pebbles);
#   "meadow": in drifts on the lushest open ground away from trees (flowers, petals, tall grass);
#   "rare":   a few single accents per chunk (boulders, a standing stone).
# chance: share of anchors that get any; per: [min, max] pieces at such an anchor; ring: [min, max] metres from it.
const DECOR := [
	{"file": "Fern_1", "anchor": "tree", "chance": 0.55, "per": [1, 4], "ring": [0.8, 3.6], "scale": [0.6, 1.7], "biomes": ["forest", "swamp", "plains"], "range": 110.0},
	{"file": "Bush_Common", "anchor": "tree", "chance": 0.3, "per": [1, 2], "ring": [1.4, 3.8], "scale": [0.8, 1.6], "biomes": ["forest", "plains", "swamp"], "range": 170.0},
	{"file": "Plant_1_Big", "anchor": "tree", "chance": 0.08, "per": [1, 1], "ring": [1.0, 3.0], "scale": [0.8, 1.2], "biomes": ["forest", "swamp"], "range": 130.0},
	{"file": "Mushroom_Common", "anchor": "tree", "chance": 0.22, "per": [1, 3], "ring": [0.5, 1.6], "scale": [0.7, 1.6], "biomes": ["forest", "swamp"], "range": 70.0},
	{"file": "Mushroom_Laetiporus", "anchor": "tree", "chance": 0.08, "per": [1, 2], "ring": [0.4, 1.0], "scale": [0.8, 1.4], "biomes": ["forest", "swamp"], "range": 70.0},
	{"file": "Pebble_Round_1", "anchor": "rock", "chance": 0.8, "per": [2, 6], "ring": [0.9, 2.8], "scale": [0.4, 2.2], "biomes": ["forest", "plains", "beach", "mountain", "swamp"], "range": 80.0},
	{"file": "Pebble_Square_2", "anchor": "rock", "chance": 0.5, "per": [1, 3], "ring": [1.0, 3.0], "scale": [0.6, 1.8], "biomes": ["plains", "beach", "mountain"], "range": 80.0},
	{"file": "Flower_3_Group", "anchor": "meadow", "chance": 1.0, "per": [10, 18], "ring": [0.0, 4.5], "scale": [0.8, 1.3], "biomes": ["plains", "forest"], "range": 95.0},
	{"file": "Flower_4_Group", "anchor": "meadow", "chance": 0.8, "per": [8, 14], "ring": [0.0, 4.0], "scale": [0.8, 1.3], "biomes": ["plains"], "range": 95.0},
	{"file": "Flower_3_Single", "anchor": "meadow", "chance": 1.0, "per": [8, 14], "ring": [1.5, 6.5], "scale": [0.8, 1.4], "biomes": ["plains", "forest", "beach"], "range": 70.0},
	{"file": "Flower_4_Single", "anchor": "meadow", "chance": 0.8, "per": [6, 12], "ring": [1.5, 6.5], "scale": [0.8, 1.4], "biomes": ["plains"], "range": 70.0},
	{"file": "Bush_Common_Flowers", "anchor": "meadow", "chance": 0.6, "per": [1, 2], "ring": [4.0, 7.0], "scale": [0.8, 1.4], "biomes": ["forest", "plains"], "range": 170.0},
	{"file": "Grass_Wispy_Tall", "anchor": "meadow", "chance": 0.7, "per": [4, 8], "ring": [3.0, 7.5], "scale": [0.8, 2.0], "biomes": ["plains", "swamp", "beach"], "range": 95.0},
	{"file": "Petal_1", "anchor": "meadow", "chance": 0.6, "per": [3, 6], "ring": [0.0, 3.5], "scale": [0.8, 1.6], "biomes": ["plains", "forest"], "range": 50.0},
]
const MEADOWS_PER_CHUNK := 3
const MEADOW_CLEARANCE := 7.0 # Metres from the nearest tree for a meadow's heart.


static func _on_road(pieces: Array, point: Vector2, clearance: float) -> bool:
	for piece in pieces:
		var a: Vector2 = piece[0]
		var ab: Vector2 = piece[1] - a
		var t: float = clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if point.distance_to(a + ab * t) < clearance:
			return true
	return false


## Where the meadows' hearts are in this chunk: the lushest open spots, well away from trees and roads.
func _meadow_centers(origin: Vector2, trees: Array, road_pieces: Array) -> Array:
	var candidates: Array = []
	for j in 8:
		for i in 8:
			var spot := origin + Vector2(float(i) + 0.5, float(j) + 0.5) * (Defs.CHUNK_SIZE / 8.0)
			var lush: float = GrassField.lushness(spot.x, spot.y)
			if lush < 0.55 or _world.is_water(spot.x, spot.y) or _on_road(road_pieces, spot, 4.0):
				continue
			var open := true
			for tree in trees:
				if spot.distance_squared_to(tree) < MEADOW_CLEARANCE * MEADOW_CLEARANCE:
					open = false
					break
			if open:
				candidates.append([lush, spot])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var picked: Array = []
	for candidate in candidates:
		var spot: Vector2 = candidate[1]
		var spaced := true
		for other in picked:
			if spot.distance_to(other) < 18.0:
				spaced = false
				break
		if spaced:
			picked.append(spot)
		if picked.size() >= MEADOWS_PER_CHUNK:
			break
	return picked


## Positions for one decor entry around its anchors (world x, z), clipped to this chunk and kept off water and roads.
func _anchored_spots(entry: Dictionary, anchors: Array, origin: Vector2, rng: RandomNumberGenerator, road_pieces: Array, road_clear: float) -> Array:
	var spots: Array = []
	var ring: Array = entry.get("ring", [0.5, 3.0])
	var per: Array = entry.get("per", [1, 1])
	for anchor in anchors:
		if rng.randf() > float(entry.get("chance", 1.0)):
			continue
		for k in rng.randi_range(int(per[0]), int(per[1])):
			# Denser toward the anchor (square-root falloff would spread evenly; a plain random radius gathers them).
			var at: Vector2 = anchor + Vector2.from_angle(rng.randf() * TAU) * lerpf(float(ring[0]), float(ring[1]), rng.randf())
			if at.x < origin.x or at.y < origin.y or at.x >= origin.x + Defs.CHUNK_SIZE or at.y >= origin.y + Defs.CHUNK_SIZE:
				continue
			if _world.is_water(at.x, at.y) or not (_world.biome_at(at.x, at.y) in entry["biomes"]) or _on_road(road_pieces, at, road_clear):
				continue
			spots.append(at)
	return spots


func _build_decor(origin: Vector2, rng: RandomNumberGenerator, data: Dictionary) -> void:
	if _raw_heights.size() == SAMPLES * SAMPLES and _biome_names.size() == BIOME_TEXELS * BIOME_TEXELS:
		_grass_source = GrassField.Source.new(origin, _raw_heights, SAMPLES, _biome_names, BIOME_TEXELS, _road_data, _patches)
		set_process(true)
	var center := origin + Vector2.ONE * Defs.CHUNK_SIZE * 0.5
	if center.length() < Defs.HUB_SAFE_RADIUS + 30.0:
		return # The hub is paved.
	# Nothing grows on the roads (they are 1 m wider here than the drawn dirt, so blades never lean onto it).
	var road_pieces: Array = _world.roads.pieces_in_cell(cell) if _world.roads != null else []
	var road_clear: float = WorldRoads.HALF_WIDTH + 1.0
	var anchors := {"tree": [], "rock": [], "meadow": [], "rare": [], "ruin": []}
	for node in data.get("nodes", []):
		var at := Vector2(float(node["x"]), float(node["z"]))
		match str(node["kind"]):
			"tree":
				anchors["tree"].append(at)
			"rock", "ore":
				anchors["rock"].append(at)
	# Ruin decorations follow actual abandoned buildings, not ordinary settlements.
	for structure in data.get("structures", []):
		var structure_kind: String = str(structure.get("kind", ""))
		if structure_kind == "ruin" or (bool(data.get("ruin", false)) and structure_kind in ["building", "wall"]):
			anchors["ruin"].append(Vector2(float(structure["x"]), float(structure["z"])))
	anchors["meadow"] = _meadow_centers(origin, anchors["tree"], road_pieces)
	for k in 2:
		anchors["rare"].append(origin + Vector2(rng.randf(), rng.randf()) * Defs.CHUNK_SIZE)
	if _use_nature:
		for entry in DECOR:
			var file := String(entry["file"])
			var mesh: Mesh = Foliage.swayed(Assets.nature_mesh(file), "decor:" + file, 0.0 if file.begins_with("Pebble") or file.begins_with("Petal") else (0.2 if file.begins_with("Grass") else 0.12))
			if mesh == null:
				continue
			var places: Array = _anchored_spots(entry, anchors[str(entry["anchor"])], origin, rng, road_pieces, road_clear)
			if places.is_empty():
				continue
			var transforms: Array[Transform3D] = []
			for i in places.size():
				var at: Vector2 = places[i]
				var size := rng.randf_range(float(entry["scale"][0]), float(entry["scale"][1]))
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size)
				transforms.append(Transform3D(basis, Vector3(at.x - origin.x, _world.height_at(at.x, at.y) - 0.02, at.y - origin.y)))
			# Dense vegetation is split into camera-cullable cells, sparse props remain one draw call.
			for decor_batch in SceneryBatches.add(self, mesh, transforms, float(entry["range"]), file.begins_with("Bush")):
				register_scenery(decor_batch, "decor:" + file, float(entry["range"]))
				if file.begins_with("Bush"):
					_shadow_casters.append({"node": decor_batch, "role": "bush", "bounds": decor_batch.custom_aabb})
	# Logs, branches, roots, scree and the odd standing stone, each where it belongs.
	for entry in ModelCatalog.available("decor", ModelCatalog.DECOR_EXTRA):
		var extra_mesh: Mesh = ModelCatalog.entry_mesh(entry)
		if extra_mesh == null:
			continue
		var size_range: Array = entry.get("scale", [0.8, 1.3])
		var group: int = int(entry.get("group", 0))
		var placed: Array = [] # [position, scale]
		for at in _anchored_spots(entry, anchors[str(entry.get("anchor", "rare"))], origin, rng, road_pieces, road_clear):
			# Sizes lean small: many little ones, now and then a big one.
			var t: float = rng.randf()
			var main_scale: float = lerpf(float(size_range[0]), float(size_range[1]), t * t)
			placed.append([at, main_scale])
			# A few smaller ones lying around it, as stones and sticks really do.
			for k in group:
				var around: Vector2 = at + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.8, 2.6) * main_scale
				if around.x < origin.x or around.y < origin.y or around.x >= origin.x + Defs.CHUNK_SIZE or around.y >= origin.y + Defs.CHUNK_SIZE or _world.is_water(around.x, around.y):
					continue
				placed.append([around, main_scale * rng.randf_range(0.25, 0.6)])
		if placed.is_empty():
			continue
		var transforms: Array[Transform3D] = []
		for i in placed.size():
			var where: Vector2 = placed[i][0]
			# Tilted a little, sunk a little: lying in the ground for ages, not placed on it.
			var basis := Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.12))
			basis = basis.scaled(Vector3.ONE * float(placed[i][1]))
			transforms.append(Transform3D(basis, Vector3(where.x - origin.x, _world.height_at(where.x, where.y) - 0.06 * float(placed[i][1]), where.y - origin.y)))
		for extra_batch in SceneryBatches.add(self, extra_mesh, transforms, 140.0):
			register_scenery(extra_batch, "decor:extra", 140.0)


## Rebuild the tiny 64x64 L8 mask only when a world object disappears.
## The fallback ground material may be shared by many chunks, so duplicate it
## before binding the chunk's contact texture and UV origin.
func _refresh_ground_contact() -> void:
	if _terrain == null:
		return
	var material: ShaderMaterial = _terrain.material as ShaderMaterial
	if material == null:
		return
	if not _contact_material_private:
		material = material.duplicate() as ShaderMaterial
		_terrain.material = material
		_contact_material_private = true
	material.set_shader_parameter("contact_map", GroundContactAO.create_texture(
		WorldGen.cell_origin(cell), Defs.CHUNK_SIZE,
		_contact_nodes, _contact_structures, _hidden))
	material.set_shader_parameter("chunk_origin", WorldGen.cell_origin(cell))
	material.set_shader_parameter("chunk_size", Defs.CHUNK_SIZE)


## Hides depleted nodes and opened crates. `hidden_ids` is the set of ids the server says are gone.
func apply_state(hidden_ids: Dictionary) -> void:
	var changed := false
	for kind in _groups:
		var group: Dictionary = _groups[kind]
		for id in group["index"]:
			var should_hide: bool = hidden_ids.has(id)
			if should_hide == _hidden.has(id):
				continue
			changed = true
			var i: int = group["index"][id]
			if should_hide:
				_hidden[id] = true
				group["multimesh"].set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.001), group["transforms"][i].origin))
			else:
				_hidden.erase(id)
				group["multimesh"].set_instance_transform(i, group["transforms"][i])
	if changed and _terrain != null:
		_refresh_ground_contact()
