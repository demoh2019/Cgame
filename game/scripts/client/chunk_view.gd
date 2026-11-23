extends Node3D
## The visual side of one world chunk: its terrain and every tree, rock, bush and crate in it.
## Nothing here is sent over the network. It is built from the seed, and only the "depleted" and
## "opened" flags from the server change what is shown.

const Defs = preload("res://scripts/shared/defs.gd")
const ResourceGathering = preload("res://scripts/shared/resource_gathering.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const StoneResources = preload("res://scripts/shared/stone_resources.gd")
const SolidScenery = preload("res://scripts/shared/solid_scenery.gd")
const LootCachePalette = preload("res://scripts/shared/loot_cache_palette.gd")
const GroundPlants = preload("res://scripts/client/ground_plants.gd")
const TerrainRvt = preload("res://scripts/client/terrain_rvt.gd")
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
const TerrainCurvature = preload("res://scripts/client/terrain_curvature.gd")
const TerrainHorizonAO = preload("res://scripts/client/terrain_horizon_ao.gd")
const TerrainAnisotropy = preload("res://scripts/client/terrain_anisotropy.gd")
const ObjectBatchGrid = preload("res://scripts/client/object_batch_grid.gd")
const SceneryBatches = preload("res://scripts/client/scenery_batches.gd")
const ImpostorField = preload("res://scripts/client/impostor_field.gd")
const Rendering = preload("res://scripts/native/cgame_rendering.gd") # Native cgame_rendering module when built in.
const ResourceMultiMeshUpdates = preload("res://scripts/client/multimesh_resource_updates.gd")
const ResourceInstanceInitializer = preload("res://scripts/client/resource_instance_initializer.gd")
const DecorStreamingPolicy = preload("res://scripts/client/decor_streaming_policy.gd")
const ShadowBudget = preload("res://scripts/client/shadow_budget.gd")
const DungeonLightBudget = preload("res://scripts/client/dungeon_light_budget.gd")
const DungeonReflectionBudget = preload("res://scripts/client/dungeon_reflection_budget.gd")
const OutdoorReflectionBudget = preload("res://scripts/client/outdoor_reflection_budget.gd")
const DungeonOcclusion = preload("res://scripts/client/dungeon_occlusion.gd")
const SceneryLod = preload("res://scripts/client/scenery_lod.gd")
const SceneryDensityLod = preload("res://scripts/client/scenery_density_lod.gd")
const SceneryHlodProxy = preload("res://scripts/client/scenery_hlod_proxy.gd")
const CampfireFx = preload("res://scripts/client/campfire_fx.gd")

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
global uniform float aa_terrain_curvature_strength;
global uniform float aa_terrain_horizon_ao_strength;
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
	float morph = clamp(aa_lod_morph * UV2.y, 0.0, 1.0);
	VERTEX.y = mix(VERTEX.y, UV2.x, morph);
	if (morph > 0.001) {
		// Custom0 contains the next LOD's *coarse vertex normals*. Light
		// shading now follows the same triangle transition as vertex height.
		// Performance/Balanced omit this stream; their morph is always zero.
		NORMAL = normalize(mix(NORMAL, CUSTOM0.xyz, morph));
	}
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
	float cavity = clamp(COLOR.r, 0.0, 1.0)
		* aa_terrain_curvature_strength * detail_fade;
	float ridge = clamp(COLOR.g, 0.0, 1.0)
		* aa_terrain_curvature_strength * detail_fade;
	// CPU-baked horizon openness is passed through the existing vertex B.
	float sky_visibility = 1.0;
	if (aa_terrain_horizon_ao_strength > 0.001) {
		sky_visibility = mix(1.0, clamp(COLOR.b, 0.0, 1.0),
			clamp(aa_terrain_horizon_ao_strength, 0.0, 1.0));
	}
	AO = ground_contact * (1.0 - cavity * 0.24) * sky_visibility;
	ALBEDO = color * mix(1.0, sky_visibility, 0.10)
		* (1.0 - cavity * 0.095 + ridge * 0.035)
		* mix(1.0, ground_contact, 0.12)
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
static var _solid_wood_fallbacks: Dictionary = {}
static var terrain_filter_quality := 1
static var terrain_geomorph_enabled := false
static var terrain_horizon_enabled := false
static var terrain_screen_lod_quality := 1
static var terrain_lod_pixel_error := 3.5
static var terrain_mesh_build_budget_usec := 1500
static var terrain_mesh_streaming_priority := 2
# Keep only the most recently used mesh LODs on the GPU for each terrain tile.
# Zero in the native engine remains unlimited for older scenes/tools.
static var terrain_max_cached_lods := 2
static var terrain_error_lod_quality := 1
const TERRAIN_LOD_GROUP := "aa_chunked_terrain_lod"
const TERRAIN_LAYERS := ["lush", "dry", "forest", "swamp", "road", "cliff", "mountain", "sand", "snow", "asphalt", "concrete", "brick", "plank"]
const TERRAIN_DIR := "res://assets/textures/terrain/"
const TERRAIN_PBR_DIR := "res://assets/textures/terrain_pbr/"
# Natural layers now use the photoscanned Poly Haven sets in terrain_pbr (paved layers keep their files).
const TERRAIN_SOURCES := {
	"lush": "forrest_ground_01", "dry": "aerial_rocks_01", "forest": "forest_leaves_04", "swamp": "brown_mud_03",
	"road": "rocky_trail", "cliff": "cliff_side", "mountain": "aerial_rocks_02", "sand": "coast_sand_02", "snow": "snow_02",
}
# How strongly each photo is pulled toward the art-directed biome colour (0 keeps the real photo colours).
const TERRAIN_TINT_STRENGTH := 0.25
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
var _base_curvature_colors := PackedColorArray()
var _horizon_cached := PackedFloat32Array()
var _horizon_state := -1
var _biome_names := PackedStringArray()
var _road_data := PackedByteArray()
var _patches := PackedVector4Array()
# Grass grows tile by tile once the chunk is near the camera, within a time budget per frame across all chunks.
var _grass_source
var _grass_next_tile := 0
# Cosmetic visual tasks are separate from server-authoritative resources.
var _decor_origin := Vector2.ZERO
var _decor_rng: RandomNumberGenerator
var _decor_anchors: Dictionary = {}
var _decor_road_pieces: Array = []
var _decor_road_clear := 0.0
var _decor_tasks: Array[Dictionary] = []
var _decor_next := 0
static var _decor_pending: Array[WeakRef] = []
static var _decor_last_frame := -1
static var decor_budget_usec := 1500
var _grass_tiles: Array[MultiMeshInstance3D] = []
## Density-scalable decorative flowers/grass only; no gameplay nodes.
var _density_scenery_batches: Array[MultiMeshInstance3D] = []
## Chunk-local cosmetic pebbles: several near MultiMesh variants share
## one low-poly, single-surface HLOD mesh in the distance.
var _hlod_stone_sources: Array[MultiMeshInstance3D] = []
var _hlod_stone_transforms: Array[Transform3D] = []
var _hlod_stone_centers := PackedVector3Array()
var _hlod_stone_extents := PackedVector3Array()
var _hlod_stone_overflow := false
var _hlod_stone_proxy: MeshInstance3D = null
var _hlod_stone_far := false
var _density_lod_elapsed := 0.0
const DENSITY_LOD_INTERVAL := 0.6
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
## Expensive halo sampling is restricted to High/Ultra. Switches update
## existing terrain vertices; no shader textures or new draw passes.
static func configure_terrain_horizon(quality: int) -> void:
	terrain_horizon_enabled = clampi(quality, 0, 3) >= 2


static func apply_terrain_horizon(node: Node) -> void:
	if node is ChunkedTerrain3D and node.is_in_group(TERRAIN_LOD_GROUP):
		var owner: Node = node.get_parent()
		if owner != null and owner.has_method("_refresh_terrain_horizon"):
			owner.call("_refresh_terrain_horizon")


## Like Unreal's streaming time slice, our native Godot fork amortizes
## expensive uncached terrain mesh builds across process frames. The limit
## is shared by all ChunkedTerrain3D nodes, not multiplied per world cell.
static func configure_terrain_mesh_budget(microseconds: int) -> void:
	terrain_mesh_build_budget_usec = clampi(microseconds, 0, 20000)


static func apply_terrain_mesh_budget(node: Node) -> void:
	if node is ChunkedTerrain3D and node.is_in_group(TERRAIN_LOD_GROUP):
		node.mesh_build_budget_usec = terrain_mesh_build_budget_usec


## Prioritize filling visible terrain gaps before costly LOD upgrades.
## Modes: 0=legacy order, 1=near first, 2=near + view-facing bias.
static func configure_terrain_streaming_priority(mode: int) -> void:
	terrain_mesh_streaming_priority = clampi(mode, 0, 2)


static func apply_terrain_streaming_priority(node: Node) -> void:
	if node is ChunkedTerrain3D and node.is_in_group(TERRAIN_LOD_GROUP):
		node.mesh_streaming_priority = terrain_mesh_streaming_priority


## Resident geometry, not just per-frame CPU building, needs a GPU budget.
## All LODs are still generated on demand by the native streaming scheduler.
static func configure_terrain_mesh_residency(quality: int) -> void:
	terrain_max_cached_lods = [1, 2, 2, 3][clampi(quality, 0, 3)]


## Older Cgame executables have ChunkedTerrain3D but do not yet expose its
## GPU mesh residency cap. Keep chunk creation and live graphics presets
## working until the engine binary is rebuilt from the current sources.
static func _set_terrain_mesh_residency(terrain: ChunkedTerrain3D) -> void:
	if terrain.has_method("set_max_cached_lods"):
		terrain.call("set_max_cached_lods", terrain_max_cached_lods)


static func apply_terrain_mesh_residency(node: Node) -> void:
	if node is ChunkedTerrain3D and node.is_in_group(TERRAIN_LOD_GROUP):
		_set_terrain_mesh_residency(node as ChunkedTerrain3D)


static func configure_terrain_geomorph(quality: int) -> void:
	terrain_geomorph_enabled = clampi(quality, 0, 3) >= 2


static func apply_terrain_geomorph(node: Node) -> void:
	if node is ChunkedTerrain3D:
		var terrain := node as ChunkedTerrain3D
		if terrain.has_method("set_lod_geomorph_enabled"):
			terrain.lod_geomorph_enabled = terrain_geomorph_enabled
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


## Preserve jagged ridges at distance but simplify flat plains early.
## The native engine caches height deviation once; graphics profiles only
## update a weight, with no new shader passes or terrain regeneration.
static func terrain_error_strength_for_quality(quality: int) -> float:
	return [0.0, 0.25, 0.65, 1.0][clampi(quality, 0, 3)]


static func configure_terrain_error_lod(quality: int) -> void:
	terrain_error_lod_quality = clampi(quality, 0, 3)


static func apply_terrain_error_lod(node: Node) -> void:
	if node is ChunkedTerrain3D and node.has_method("set_lod_geometric_error_strength"):
		node.call("set_lod_geometric_error_strength",
			terrain_error_strength_for_quality(terrain_error_lod_quality))


## Per-chunk geometric simplification budget in screen pixels.
## The same group includes PBR and procedural fallback terrain.
static func configure_terrain_pixel_error(pixels: float) -> void:
	# UI / autoscaler values must not leak NaN, infinity or an unbounded
	# error threshold into the native screen-space LOD selector.
	if not is_finite(pixels):
		return
	terrain_lod_pixel_error = clampf(pixels, 0.0, 20.0)


static func apply_terrain_pixel_error(terrain: Node) -> void:
	if terrain is ChunkedTerrain3D and terrain.is_in_group(TERRAIN_LOD_GROUP):
		terrain.lod_pixel_error = terrain_lod_pixel_error


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
## One shared budget for ALL loaded ChunkViews, not one limit per cell.
static func configure_decor_budget(microseconds: int) -> void:
	decor_budget_usec = clampi(microseconds, 100, 12000)


static func get_pending_decor_count() -> int:
	var count := 0
	for reference in _decor_pending:
		var view = reference.get_ref()
		if view != null and view.is_inside_tree() and view._decor_next < view._decor_tasks.size():
			count += view._decor_tasks.size() - view._decor_next
	return count


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
## Prebuilt VRAM-compressed layer arrays (tools/build_terrain_arrays.sh): 2k albedo at a 2 m tile is
## ~1024 texels per metre, the first-person target; built at import time instead of at startup.
const TERRAIN_ARRAY_DIR := "res://assets/textures/terrain_arrays/"


static func _prebuilt_material() -> ShaderMaterial:
	var albedo_path := TERRAIN_ARRAY_DIR + "terrain_albedo_array.jpg"
	var normal_path := TERRAIN_ARRAY_DIR + "terrain_normal_array.jpg"
	var height_path := TERRAIN_ARRAY_DIR + "terrain_height_array.jpg"
	if not (ResourceLoader.exists(albedo_path) and ResourceLoader.exists(normal_path) and ResourceLoader.exists(height_path)):
		return null
	var albedo_array := load(albedo_path) as Texture2DArray
	var normal_array := load(normal_path) as Texture2DArray
	var height_array := load(height_path) as Texture2DArray
	if albedo_array == null or normal_array == null or height_array == null or albedo_array.get_layers() < TERRAIN_LAYERS.size():
		return null
	var tints := PackedVector3Array()
	var averages := PackedVector3Array()
	for index in TERRAIN_LAYERS.size():
		var small: Image = albedo_array.get_layer_data(index)
		if small.is_compressed():
			small.decompress()
		small.clear_mipmaps()
		small.convert(Image.FORMAT_RGB8)
		small.resize(16, 16, Image.INTERPOLATE_BILINEAR)
		var sum := Vector3.ZERO
		for y in 16:
			for x in 16:
				var pixel: Color = small.get_pixel(x, y)
				sum += Vector3(pixel.r, pixel.g, pixel.b)
		var average: Vector3 = sum / 256.0
		var target: Color = TERRAIN_TARGETS[index]
		var full_tint := Vector3(target.r / maxf(average.x, 0.02), target.g / maxf(average.y, 0.02), target.b / maxf(average.z, 0.02))
		var tint: Vector3 = Vector3.ONE.lerp(full_tint, TERRAIN_TINT_STRENGTH)
		tints.append(tint)
		averages.append(average * tint)
	var shader: Shader = TerrainAnisotropy.shader_for_quality(terrain_filter_quality)
	if shader == null:
		return null
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("albedo_layers", albedo_array)
	material.set_shader_parameter("normal_layers", normal_array)
	material.set_shader_parameter("height_layers", height_array)
	material.set_shader_parameter("tile_meters", 2.0)
	material.set_shader_parameter("albedo_texels", 2048.0)
	material.set_shader_parameter("normal_texels", 1024.0)
	material.set_shader_parameter("biome_texels", float(BIOME_TEXELS))
	material.set_shader_parameter("layer_tint", tints)
	material.set_shader_parameter("layer_average", averages)
	return material


static func textured_material() -> ShaderMaterial:
	if _textured_checked:
		return _textured_material
	_textured_checked = true
	_textured_material = _prebuilt_material()
	if _textured_material != null:
		return _textured_material
	var albedo: Array[Image] = []
	var normals: Array[Image] = []
	var heights: Array[Image] = []
	for layer in TERRAIN_LAYERS:
		var diffuse_texture: Texture2D = null
		var normal_texture: Texture2D = null
		if TERRAIN_SOURCES.has(layer):
			var id: String = TERRAIN_SOURCES[layer]
			var folder: String = TERRAIN_PBR_DIR + id + "/" + id
			if ResourceLoader.exists(folder + "_diff.jpg") and ResourceLoader.exists(folder + "_nor_gl.jpg"):
				diffuse_texture = load(folder + "_diff.jpg") as Texture2D
				normal_texture = load(folder + "_nor_gl.jpg") as Texture2D
		if diffuse_texture == null or normal_texture == null:
			diffuse_texture = load(TERRAIN_DIR + layer + "_diff.jpg") as Texture2D
			normal_texture = load(TERRAIN_DIR + layer + "_nor_gl.jpg") as Texture2D
		if diffuse_texture == null or normal_texture == null:
			return null
		albedo.append(_layer_image(diffuse_texture, 1024))
		normals.append(_layer_image(normal_texture, 1024))
		heights.append(_height_image(layer))
	# The forked engine builds Toksvig normal mipmaps once per layer.
	# Stock Godot keeps the existing RGB8 mipmaps, with alpha=1 in sampling.
	# Avoid partially converted arrays: Texture2DArray requires one format.
	if ClassDB.class_exists("NormalVarianceMipmaps"):
		var prefilter: Object = ClassDB.instantiate("NormalVarianceMipmaps")
		if prefilter != null and prefilter.has_method("build_image"):
			var filtered_normals: Array[Image] = []
			for normal_image in normals:
				var variance_image: Image = prefilter.call("build_image", normal_image) as Image
				if variance_image == null:
					filtered_normals.clear()
					break
				filtered_normals.append(variance_image)
			if filtered_normals.size() == normals.size():
				normals = filtered_normals
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
		var full_tint := Vector3(target.r / maxf(average.x, 0.02), target.g / maxf(average.y, 0.02), target.b / maxf(average.z, 0.02))
		var tint: Vector3 = Vector3.ONE.lerp(full_tint, TERRAIN_TINT_STRENGTH)
		tints.append(tint)
		averages.append(average * tint)
	var albedo_array := Texture2DArray.new()
	var normal_array := Texture2DArray.new()
	var height_array := Texture2DArray.new()
	if height_array.create_from_images(heights) == OK:
		pass
	if albedo_array.create_from_images(albedo) != OK or normal_array.create_from_images(normals) != OK:
		return null
	var shader: Shader = TerrainAnisotropy.shader_for_quality(terrain_filter_quality)
	if shader == null:
		return null
	_textured_material = ShaderMaterial.new()
	_textured_material.shader = shader
	_textured_material.set_shader_parameter("albedo_layers", albedo_array)
	_textured_material.set_shader_parameter("normal_layers", normal_array)
	_textured_material.set_shader_parameter("height_layers", height_array)
	_textured_material.set_shader_parameter("biome_texels", float(BIOME_TEXELS))
	_textured_material.set_shader_parameter("layer_tint", tints)
	_textured_material.set_shader_parameter("layer_average", averages)
	return _textured_material


## An imported texture as a plain RGB image of a fixed size with mipmaps, so all layers of an array match.
## The layer's Poly Haven displacement as a 512 px L8 image with mipmaps, or flat grey when it has none.
static func _height_image(layer: String) -> Image:
	var image: Image = null
	if TERRAIN_SOURCES.has(layer):
		var id: String = TERRAIN_SOURCES[layer]
		var path: String = TERRAIN_PBR_DIR + id + "/" + id + "_disp.jpg"
		if ResourceLoader.exists(path):
			var texture := load(path) as Texture2D
			if texture != null:
				image = texture.get_image()
	if image == null:
		image = Image.create(512, 512, false, Image.FORMAT_L8)
		image.fill(Color(0.5, 0.5, 0.5))
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_L8)
	if image.get_width() != 512 or image.get_height() != 512:
		image.resize(512, 512, Image.INTERPOLATE_BILINEAR)
	image.clear_mipmaps()
	image.generate_mipmaps()
	return image


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
	var data: PackedByteArray = WorldRoads.rasterize_mask(pieces, origin, size)
	_road_data = data
	return ImageTexture.create_from_image(Image.create_from_data(size, size, false, Image.FORMAT_L8, data))

func build(p_world, p_cell: Vector2i) -> void:
	_use_nature = Assets.has_nature()
	_use_village = Assets.has_village()
	_world = p_world
	cell = p_cell
	GrassField.rivers = _world.rivers
	# Stagger 0.5-second shadow checks across neighboring chunks to avoid update spikes.
	_shadow_timer = float(posmod(cell.x * 37 + cell.y * 19, 50)) * 0.01
	var origin := WorldGen.cell_origin(cell)
	if Dungeon.is_underground(origin.x + Defs.CHUNK_SIZE):
		_build_dungeon(origin)
		_build_objects(_world.chunk(cell)) # The chests.
		return
	_build_terrain(origin)
	_build_rivers_and_bridges(origin)
	var data: Dictionary = _world.chunk(cell)
	_build_objects(data)
	_add_outdoor_reflection_anchors(origin, data)
	_layer_sites = data.get("pois", [])
	set_data_layers(active_layers)


## Only the containing chunk creates a cheap site marker, never a GPU probe.
## The single world-wide reflection manager captures at most 1/2 nearby sites.
func _add_outdoor_reflection_anchors(origin: Vector2, data: Dictionary) -> void:
	for site in data.get("pois", []):
		var kind: String = str(site.get("kind", ""))
		if not OutdoorReflectionBudget.SITE_KINDS.has(kind):
			continue
		var x: float = float(site["x"])
		var z: float = float(site["z"])
		if not OutdoorReflectionBudget.belongs_to_chunk(x, z, origin, Defs.CHUNK_SIZE):
			continue
		var anchor := Node3D.new()
		anchor.name = "OutdoorReflectionAnchor"
		anchor.position = Vector3(x - origin.x,
			float(_world.height_at(x, z)) + 3.5, z - origin.y)
		anchor.add_to_group(OutdoorReflectionBudget.GROUP)
		add_child(anchor)


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
			# Living HDR flame on the torch model (bloom-lit; the light stays budgeted).
			CampfireFx.add_torch_flame(_kit("torch_mounted", torch_at + Vector3(0, 1.4, 0), 0.0, 0.5))
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


## Cache native horizon AO on demand. All terrain LODs share the existing
## vertex color stream (R cavity, G ridges, B sky visibility); lighting
## quality switches never change collision or authoritative world state.
func _refresh_terrain_horizon() -> void:
	if _terrain == null:
		return
	var desired: int = 1 if terrain_horizon_enabled else 0
	if _horizon_state == desired:
		return
	var origin: Vector2 = WorldGen.cell_origin(cell)
	var spacing: float = Defs.CHUNK_SIZE / float(SAMPLES - 1)
	var height_sampler := Callable(_world, "ground_at")
	if _base_curvature_colors.is_empty():
		_base_curvature_colors = TerrainCurvature.build(
			_raw_heights, origin, SAMPLES, spacing, height_sampler)
	var colors: PackedColorArray = _base_curvature_colors
	if terrain_horizon_enabled:
		if _horizon_cached.is_empty():
			_horizon_cached = TerrainHorizonAO.build(
				_raw_heights, origin, SAMPLES, spacing, height_sampler,
				HEIGHT_MIN, HEIGHT_MIN + HEIGHT_RANGE)
		if _horizon_cached.size() == colors.size():
			colors = _base_curvature_colors.duplicate()
			for i in colors.size():
				var pixel: Color = colors[i]
				pixel.b = _horizon_cached[i]
				colors[i] = pixel
	# Color-only edits avoid resetting neighboring LOD and collision caches.
	if _terrain.has_method("apply_color_patch") and _terrain.get_color_data().size() == colors.size():
		_terrain.apply_color_patch(Rect2i(0, 0, SAMPLES, SAMPLES), colors)
	else:
		_terrain.set_color_data(colors)
	_horizon_state = desired


func _build_terrain(origin: Vector2) -> void:
	var heights := PackedFloat32Array()
	var sample_count: int = SAMPLES * SAMPLES
	heights.resize(sample_count)
	# Preserve a fixed-size raw buffer for grass, normals and horizon AO.
	# Indexed writes avoid thousands of repeated PackedArray appends per chunk.
	_raw_heights.resize(sample_count)
	_base_curvature_colors.clear()
	_horizon_cached.clear()
	_horizon_state = -1
	var step := Defs.CHUNK_SIZE / float(SAMPLES - 1)
	for j in SAMPLES:
		for i in SAMPLES:
			var h: float = _world.ground_at(origin.x + i * step, origin.y + j * step)
			var index: int = j * SAMPLES + i
			heights[index] = clampf((h - HEIGHT_MIN) / HEIGHT_RANGE, 0.0, 1.0)
			_raw_heights[index] = h
	_terrain = ChunkedTerrain3D.new()
	_terrain.centered = false
	_terrain.size = Vector2(Defs.CHUNK_SIZE, Defs.CHUNK_SIZE)
	_terrain.height_scale = HEIGHT_RANGE
	_terrain.height_offset = HEIGHT_MIN
	_terrain.chunk_quads = 16
	_terrain.lod_count = 3
	_terrain.lod_distance = 70.0
	apply_terrain_screen_lod(_terrain)
	_terrain.lod_pixel_error = terrain_lod_pixel_error
	# Must be set before add_child() triggers native initial mesh streaming.
	_terrain.mesh_build_budget_usec = terrain_mesh_build_budget_usec
	_terrain.mesh_streaming_priority = terrain_mesh_streaming_priority
	_set_terrain_mesh_residency(_terrain)
	apply_terrain_error_lod(_terrain)
	if _terrain.has_method("set_lod_geomorph_enabled"):
		_terrain.lod_geomorph_enabled = terrain_geomorph_enabled
	_terrain.skirt_depth = 3.0
	_terrain.collision_enabled = false # The server decides where players can stand.
	_terrain.cast_shadows = false
	# Native ChunkedTerrain3D uses raw RenderingServer RIDs, not
	# GeometryInstance3D; explicitly include the static heightfield in
	# optional Ultra SDFGI. No extra cascades or shadow atlas allocations
	# exist on Performance/Balanced/High.
	if _terrain.has_method("set_contribute_to_gi"):
		_terrain.contribute_to_gi = true
	# Also on the layer the terrain runtime virtual texture's bake cameras see (terrain_rvt.gd).
	if "render_layers" in _terrain:
		_terrain.render_layers = TerrainRvt.terrain_layers()
	_terrain.update_interval = 0.16 if terrain_geomorph_enabled else 0.5
	_terrain.material = _ground_with_roads(origin)
	_terrain.set_height_data(heights, Vector2i(SAMPLES, SAMPLES))
	# The forked ChunkedTerrain3D accepts normals sampled one grid step past
	# the current chunk. Their shared world-space derivative removes bright
	# vertical lighting seams without an extra shader pass or texture.
	if _terrain.has_method("set_normal_data"):
		_terrain.set_normal_data(TerrainSeamNormals.build(_raw_heights, origin,
			SAMPLES, step, HEIGHT_MIN, HEIGHT_RANGE, Callable(_world, "ground_at")))
	_refresh_terrain_horizon()
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


## Filter each biome once when the optional painted tree pack is absent.
## Retain duplicate model entries: they are intentional spawn probabilities.
## Unknown biomes use the same forest fallback as before, without unbounded keys.
static var _trees_without_painted: Dictionary = {}


static func _tree_options_for_biome(biome: String, painted_available: bool) -> Array:
	var key: String = biome if TREES_BY_BIOME.has(biome) else "forest"
	if painted_available:
		return TREES_BY_BIOME[key]
	if not _trees_without_painted.has(key):
		var filtered: Array = []
		var source: Array = TREES_BY_BIOME[key]
		for option in source:
			if not str(option).begins_with("painted"):
				filtered.append(option)
		_trees_without_painted[key] = filtered
	return _trees_without_painted[key]


## Which tree stands at a node: by biome, stable for the node id.
func _tree_key(node: Dictionary, painted_available: bool) -> String:
	var biome: String = _world.biome_at(float(node["x"]), float(node["z"]))
	var options: Array = _tree_options_for_biome(biome, painted_available)
	return "tree:" + str(options[WorldGen.mix(int(node["id"]), 3, 5) % options.size()])


## A missing optional nature pack must not turn a hand-sized pickup
## into a visually huge generic boulder. Shared across chunks (one mesh/material).
static var _pebble_fallback_cache: Mesh


static func pebble_fallback_mesh() -> Mesh:
	if _pebble_fallback_cache == null:
		var pebble := SphereMesh.new()
		pebble.radius = 0.18
		pebble.height = 0.26
		pebble.radial_segments = 8
		pebble.rings = 4
		var stone_material := StandardMaterial3D.new()
		stone_material.albedo_color = Color(0.45, 0.44, 0.43)
		stone_material.roughness = 0.96
		pebble.material = stone_material
		_pebble_fallback_cache = pebble
	return _pebble_fallback_cache


## Mesh of a group. Kinds with a number ("tree:3", "building:5") are variants; the catalog picks the model installed for it,
## and each branch falls back to the Kenney or procedural models when its packs are missing.
func _mesh_for(kind: String) -> Mesh:
	if kind.begins_with("solid_wood:"):
		var variant: int = int(kind.get_slice(":", 1))
		if variant >= 0 and variant < SolidScenery.MODELS.size():
			var entry: Dictionary = SolidScenery.MODELS[variant]
			if ModelCatalog.exists(str(entry["path"])):
				var wood_mesh: Mesh = ModelCatalog.entry_mesh(entry)
				if wood_mesh != null:
					return wood_mesh
			# No downloaded pack: the same physical node is still visible.
			if not _solid_wood_fallbacks.has(variant):
				var fallback := BoxMesh.new()
				fallback.size = Vector3(float(entry["size"]), 0.55, 0.65)
				var material := StandardMaterial3D.new()
				material.albedo_color = Color(0.34, 0.23, 0.14)
				fallback.material = material
				_solid_wood_fallbacks[variant] = fallback
			return _solid_wood_fallbacks[variant]
		return Meshes.get_mesh("tree")
	if kind.begins_with("stone:"):
		var model_index: int = int(kind.get_slice(":", 1))
		if model_index >= 0 and model_index < StoneResources.MODELS.size():
			var entry: Dictionary = StoneResources.MODELS[model_index]
			var model: Mesh = null
			if entry.has("nature"):
				if _use_nature:
					model = Assets.nature_mesh(str(entry["nature"]))
				if model == null:
					model = pebble_fallback_mesh()
			else:
				model = ModelCatalog.entry_mesh(entry)
			if model != null:
				return model
		return Meshes.get_mesh("rock")
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
		"branch":
			var stick := BoxMesh.new()
			stick.size = Vector3(0.82, 0.07, 0.11)
			var bark := StandardMaterial3D.new()
			bark.albedo_color = Color(0.35, 0.23, 0.14)
			bark.roughness = 1.0
			stick.material = bark
			return stick
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
	if kind.begins_with("solid_wood:"):
		return float(node.get("scale", 1.0))
	if str(node.get("kind", "")) == "pebble" and not node.has("stone_model"):
		return 0.22
	if str(node.get("kind", "")) == "branch":
		return 1.0
	var base: String = kind.get_slice(":", 0)
	var variant: int = int(kind.get_slice(":", 1)) if kind.contains(":") else 0
	var baked: bool = _is_baked(base, variant)
	if kind.begins_with("tree:TwistedTree"):
		return rng.randf_range(0.45, 0.6)
	if kind.begins_with("monument:"):
		return 1.0 if ModelCatalog.monument(int(kind.get_slice(":", 1))) != null else 3.0
	match base:
		"stone":
			return float(node.get("scale", 1.0))
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
	var painted_available: bool = ModelCatalog.has_painted_trees() if _use_nature else false
	if _use_nature:
		tree_variants = Assets.TREE_FILES.size() + (ModelCatalog.PAINTED_TREES.size() if painted_available else 0)
	var rock_variants: int = Assets.ROCK_FILES.size() + (ModelCatalog.STONES.size() if ModelCatalog.has_stones() else 0)
	if ModelCatalog.has_scanned_rocks():
		rock_variants = ModelCatalog.SCANNED_ROCKS.size()
	var crystal_count: int = ModelCatalog.available("crystals", ModelCatalog.CRYSTALS).size()
	# Group everything that shares a mesh, so each group is one draw call.
	var by_kind: Dictionary = {}
	for node in data["nodes"]:
		var kind: String = node["kind"]
		var variant: int = WorldGen.mix(int(node["id"]), 3, 5)
		if node.has("solid_model"):
			kind = "solid_wood:%d" % int(node["solid_model"])
		elif node.has("stone_model"):
			kind = "stone:%d" % int(node["stone_model"])
		elif kind == "tree":
			kind = _tree_key(node, painted_available) if _use_nature else "tree:%d" % (variant % tree_variants)
		elif kind == "pebble":
			kind = "rock:%d" % (variant % rock_variants)
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
		transforms.resize(list.size())
		var tints := PackedColorArray()
		tints.resize(list.size())
		var is_tree: bool = kind.begins_with("tree:")
		var is_mineral: bool = kind.begins_with("rock") or kind.begins_with("ore") or kind.begins_with("stone:")
		var is_building: bool = kind.begins_with("wall") or kind.begins_with("building:") or kind.begins_with("tower") or kind == "workbench" or kind.begins_with("ruin:") or kind.begins_with("monument:")
		for i in list.size():
			var node: Dictionary = list[i]
			var size: float = _size_for(kind, node, rng)
			var yaw: float = float(node["yaw"]) if node.has("yaw") else rng.randf() * TAU
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size)
			var sink: float = 0.05 if (is_building or kind == "crate") else 0.0
			var transform := Transform3D(basis, Vector3(node["x"] - origin.x, node["y"] - sink, node["z"] - origin.y))
			# Keep the original tier tint exactly as before; submit the
			# complete group only after every resource slot is prepared.
			var tier: int = node.get("tier", 1)
			if is_mineral:
				tints[i] = Color.WHITE.lerp(Color(0.8, 0.85, 1.0), (tier - 1) * 0.2)
			elif kind.begins_with("crate:"):
				# Reuse the existing per-instance MultiMesh color buffer.
				# Special caches stay in ordinary crate batches (no extra draws).
				tints[i] = LootCachePalette.tint(node)
			else:
				tints[i] = Color.WHITE.darkened((tier - 1) * 0.07) if is_tree else Color.WHITE
			if node.has("id"):
				index[node["id"]] = i
			transforms[i] = transform
		# Dense groups upload one complete GPU-ready buffer; tiny batches
		# retain the original per-instance calls. Both preserve tier tints.
		if not ResourceInstanceInitializer.initialize(multimesh, transforms, tints):
			push_error("Invalid resource MultiMesh initialization: %s" % str(batch_id))
			continue
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (kind.begins_with("tree:") or kind.begins_with("building:") or kind.begins_with("wall") or kind.begins_with("tower") or kind.begins_with("ruin:") or kind.begins_with("monument:") or kind.begins_with("solid_wood:")) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _use_nature and kind.begins_with("ore:") and crystal_count == 0:
			instance.material_override = _ore_material(multimesh.mesh)
		register_scenery(instance, kind)
		add_child(instance)
		if instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and multimesh.mesh != null:
			# The nearest tree in a MultiMesh group matters more than the chunk centre.
			_shadow_casters.append({"node": instance, "role": "tree" if kind.begins_with("tree:") else "structure",
				"bounds": SceneryBatches.bounds_for(multimesh.mesh, transforms)})
		_groups[batch_id] = {"multimesh": multimesh, "index": index, "transforms": transforms, "tree": kind.begins_with("tree:")}
		for i in list.size():
			var harvest_node: Dictionary = list[i]
			var strikes: int = ResourceGathering.strikes_needed(str(harvest_node.get("kind", "")))
			if strikes > 0 and harvest_node.has("id"):
				_resource_damage_slots[int(harvest_node["id"])] = {
					"mesh": multimesh, "slot": i, "tint": tints[i], "total": strikes,
				}
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


## WorldStreamer only requests cosmetic simulation changes. Terrain, collision,
## loot, and server-authoritative entities remain resident and unchanged.
var _streaming_simulation_active := true
var _streaming_tick_interval := 0.0
var _streaming_tick_accumulated := 0.0


## Native WorldStreamer can request a reduced cosmetic tick frequency for
## distant but still simulation-active chunks. Physics/network/gameplay are
## not controlled by this scene. Zero restores full frame-rate processing.
func set_streaming_tick_interval(seconds: float) -> void:
	if not is_finite(seconds):
		return
	var clamped: float = clampf(seconds, 0.0, 1.0)
	if is_equal_approx(clamped, _streaming_tick_interval):
		return
	_streaming_tick_interval = clamped
	_streaming_tick_accumulated = clamped


## Only immutable client-generated scenery may use WorldStreamer's optional
## bounded detached-node cache. This chunk never owns server authority.
func can_cache_streaming_chunk() -> bool:
	return true


## Conservative cached-scene estimate. Shared shader/texture assets are
## excluded to avoid double counting; this does not measure RAM or VRAM.
func get_streaming_cache_cost_bytes() -> int:
	var bytes: int = 8 * 1048576
	bytes += _raw_heights.size() * 4
	bytes += _base_curvature_colors.size() * 16
	bytes += _horizon_cached.size() * 4
	bytes += _road_data.size()
	bytes += _patches.size() * 16
	bytes += _grass_tiles.size() * 262144
	bytes += _groups.size() * 1048576
	bytes += _decor_tasks.size() * 256
	if _hlod_stone_proxy != null and is_instance_valid(_hlod_stone_proxy) and \
			_hlod_stone_proxy.mesh != null:
		# Conservative estimate for static faceted vertex+normal buffer.
		bytes += _hlod_stone_proxy.mesh.surface_get_array_len(0) * 32
	bytes += get_child_count() * 16384
	return maxi(1, bytes)


## Reattached scenes never rerun _ready(). Restore deferred decor queue
## membership and force grass/shadow LOD checks near the new camera position.
func on_streaming_cache_restored() -> void:
	_grass_lod_elapsed = GRASS_LOD_INTERVAL
	_grass_last_eye = Vector2.INF
	_density_lod_elapsed = DENSITY_LOD_INTERVAL
	_shadow_timer = SHADOW_INTERVAL
	_shadow_last_eye = Vector2.INF
	_streaming_tick_accumulated = _streaming_tick_interval
	if _decor_next < _decor_tasks.size():
		var queued := false
		for reference in _decor_pending:
			if reference.get_ref() == self:
				queued = true
				break
		if not queued:
			_decor_pending.append(weakref(self))
	set_process(_streaming_simulation_active)


## Surface-only decorative processing; the engine may suspend this named
## layer when the observer enters a dungeon. Meshes, terrain collisions and
## real server entities remain resident and unaffected.
func get_streaming_simulation_layer() -> StringName:
	return &"SurfaceCosmetics"


func set_streaming_simulation_active(active: bool) -> void:
	if _streaming_simulation_active == active:
		return
	_streaming_simulation_active = active
	set_process(active)
	if active:
		# Re-evaluate blades and cosmetic rate immediately after LOD recovery.
		_grass_lod_elapsed = GRASS_LOD_INTERVAL
		_density_lod_elapsed = DENSITY_LOD_INTERVAL
		_streaming_tick_accumulated = _streaming_tick_interval


func _process(delta: float) -> void:
	if not _shaking.is_empty() or not _falling.is_empty() or _state_seen_pending != _state_seen:
		_animate_vegetation(delta)
	# A cheap accumulator skips expensive per-chunk grass/decor/shadow work.
	# Accumulated elapsed time keeps windmill rotation speed correct.
	# The near tier (interval = 0) remains exactly the original code path.
	if _streaming_tick_interval > 0.0:
		_streaming_tick_accumulated += delta
		if _streaming_tick_accumulated < _streaming_tick_interval:
			return
		delta = _streaming_tick_accumulated
		_streaming_tick_accumulated = 0.0
	_service_decor(self)
	_grow_grass()
	_grass_lod_elapsed += delta
	if _grass_lod_elapsed >= GRASS_LOD_INTERVAL:
		_grass_lod_elapsed = 0.0
		_update_grass_lods()
	_density_lod_elapsed += delta
	if _density_lod_elapsed >= DENSITY_LOD_INTERVAL:
		_density_lod_elapsed = 0.0
		_update_decor_density_lods()
		_update_hlod_stones()
	_shadow_timer += delta
	if _shadow_timer >= SHADOW_INTERVAL:
		_shadow_timer = 0.0
		_update_shadow_casters()
	for sail in _sails:
		(sail["node"] as Node3D).rotate_object_local(sail["axis"], sail["speed"] * delta)


## Update only visual foliage instance counts: no GPU buffer rebuilds, scene
## removals or changes to collectible/interactive world resources.
func _update_decor_density_lods() -> void:
	if _density_scenery_batches.is_empty():
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	SceneryDensityLod.update_instances_projected(_density_scenery_batches,
		camera, scenery_quality)


## HLOD replaces multiple decorative pebble MultiMeshes with one coarse
## ArrayMesh at long range. A single stable 0.6-second update is shared with
## foliage scalability; original transforms are retained for near-camera use.
func _update_hlod_stones() -> void:
	if _hlod_stone_proxy == null or not is_instance_valid(_hlod_stone_proxy):
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var proxy_center: Vector3 = _hlod_stone_proxy.to_global(
		_hlod_stone_proxy.get_aabb().get_center())
	var distance: float = camera.global_position.distance_to(proxy_center)
	var near_range: float = SceneryLod.range_for(
		"decor:Pebble", scenery_quality, 80.0)
	_hlod_stone_far = SceneryHlodProxy.switch_visible(
		_hlod_stone_sources, _hlod_stone_proxy, distance,
		near_range, _hlod_stone_far)


## A proxy is built after all seeded stone categories are complete. Its
## geometry is static and consists of at most 384 low-poly octahedra; there
## are no per-frame mesh rebuilds, physics bodies, or gameplay mutations.
func _finalize_hlod_stones() -> void:
	if _hlod_stone_proxy != null:
		return
	if _hlod_stone_overflow or _hlod_stone_sources.size() < 2 or \
			_hlod_stone_transforms.size() < SceneryHlodProxy.MIN_SOURCE_INSTANCES:
		# Preserve original stone batches, but drop unnecessary temporary
		# copies if a chunk cannot form a useful common far proxy.
		_hlod_stone_transforms.clear()
		_hlod_stone_centers.clear()
		_hlod_stone_extents.clear()
		return
	_hlod_stone_proxy = SceneryHlodProxy.attach_proxy(
		self, _hlod_stone_transforms, _hlod_stone_centers,
		_hlod_stone_extents, 384)
	if _hlod_stone_proxy != null:
		_update_hlod_stones()
	# Proxy and GPU batches own their geometry from now on; clear temporary
	# large transform arrays even if proxy generation fails validation.
	_hlod_stone_transforms.clear()
	_hlod_stone_centers.clear()
	_hlod_stone_extents.clear()


## Weak-reference global queue. Newly near-camera chunks take precedence, and
## completed/unloaded chunks vanish without retaining their world resources.
static func _service_decor(host: Node3D) -> void:
	var frame: int = Engine.get_process_frames()
	if _decor_last_frame == frame:
		return
	_decor_last_frame = frame
	if _decor_pending.is_empty():
		return
	var camera: Camera3D = host.get_viewport().get_camera_3d()
	var candidates: Array[Dictionary] = []
	var alive: Array[WeakRef] = []
	for reference in _decor_pending:
		var view = reference.get_ref()
		if view == null or not view.is_inside_tree() or view._decor_next >= view._decor_tasks.size():
			continue
		alive.append(reference)
		var score := 0.0
		if camera != null:
			var center: Vector3 = view.global_position + Vector3(
				Defs.CHUNK_SIZE * 0.5, 0.0, Defs.CHUNK_SIZE * 0.5)
			var delta: Vector3 = center - camera.global_position
			var forward: Vector3 = -camera.global_transform.basis.z
			forward.y = 0.0
			delta.y = 0.0
			var facing := 0.0
			if forward.length_squared() > 0.0001 and delta.length_squared() > 0.0001:
				facing = delta.normalized().dot(forward.normalized())
			score = DecorStreamingPolicy.rank(delta.length(), facing)
		candidates.append({"view": view, "score": score, "cell": view.cell})
	_decor_pending = alive
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["score"]), float(b["score"])):
			return float(a["score"]) < float(b["score"])
		var ac: Vector2i = a["cell"]
		var bc: Vector2i = b["cell"]
		return ac.x < bc.x if ac.x != bc.x else ac.y < bc.y)
	var elapsed := 0
	var processed := 0
	var next := 0
	while not candidates.is_empty() and DecorStreamingPolicy.can_continue(
			elapsed, decor_budget_usec, processed):
		var selected = candidates[next]["view"]
		var started: int = Time.get_ticks_usec()
		selected._build_next_decor_entry()
		elapsed += Time.get_ticks_usec() - started
		processed += 1
		if selected._decor_tasks.is_empty():
			candidates.remove_at(next)
			if candidates.is_empty():
				break
			next %= candidates.size()
		else:
			next = (next + 1) % candidates.size()


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
		# The old procedural blade grass is retired; scanned plants (below) are the grass now.
		var tile: MultiMeshInstance3D = null
		_grass_next_tile += 1
		if tile != null:
			tile.visibility_range_end = grass_visibility_end
			add_child(tile)
			tile.add_to_group(GRASS_GROUP)
			_grass_tiles.append(tile)
		# Photoscanned plants of the same tile, drawn only up close.
		var source = _grass_source
		for plant in GroundPlants.build_tile(source.origin, _grass_next_tile - 1, int(Defs.CHUNK_SIZE / GroundPlants.TILE),
				func(lx: float, lz: float) -> Dictionary: return GrassField.sample(source, lx, lz)):
			add_child(plant)
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
	# Feed real transformed AABB footprints to one bounded native HLOD plan.
	# GPU geometry stays instanced; only participating sun shadow casters change.
	var bounds_min := PackedVector3Array()
	var bounds_max := PackedVector3Array()
	var roles := PackedByteArray()
	var active_flags := PackedByteArray()
	var valid_nodes: Array[MultiMeshInstance3D] = []
	for entry in _shadow_casters:
		var caster: MultiMeshInstance3D = entry["node"]
		if not is_instance_valid(caster):
			continue
		var local_bounds: AABB = entry["bounds"]
		var world_bounds: AABB = caster.global_transform * local_bounds
		bounds_min.append(world_bounds.position)
		bounds_max.append(world_bounds.end)
		roles.append(ShadowBudget.role_index(str(entry["role"])))
		active_flags.append(1 if caster.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON else 0)
		valid_nodes.append(caster)
	var selected: PackedInt32Array = ShadowBudget.select_shadow_casters(
		bounds_min, bounds_max, roles, active_flags, eye,
		ShadowBudget.cap_for_quality(scenery_quality))
	var chosen: Dictionary = {}
	for index in selected:
		chosen[index] = true
	for i in valid_nodes.size():
		var caster: MultiMeshInstance3D = valid_nodes[i]
		var desired: bool = chosen.has(i)
		if desired != (active_flags[i] == 1):
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
	# Unreal screen-size LOD-style native batch query: ONE projection matrix
	# and ONE inverse camera transform for all tile centres. The old engine
	# and stock Godot fallback retain the same original scalar calculation.
	# Do not allocate any batch if an unchanged camera skipped this refresh.
	var tile_centers := PackedVector3Array()
	var batch_density := PackedFloat64Array()
	var batch_supported: bool = native_projection and _grass_tiles.size() <= 4096 and \
		view_camera.has_method("get_pixels_per_meter_at_positions")
	if batch_supported:
		for tile in _grass_tiles:
			tile_centers.append(to_global(tile.custom_aabb.position + tile.custom_aabb.size * 0.5))
		batch_density = view_camera.call("get_pixels_per_meter_at_positions", tile_centers)
	# The native API rejects corrupted late points atomically. A missing or
	# invalid result must never partially update the tile LOD group.
	var batch_ready: bool = batch_supported and batch_density.size() == _grass_tiles.size()
	for i in _grass_tiles.size():
		var tile: MultiMeshInstance3D = _grass_tiles[i]
		var tile_center: Vector3 = tile_centers[i] if batch_ready else \
			to_global(tile.custom_aabb.position + tile.custom_aabb.size * 0.5)
		var distance: float = camera_xz.distance_to(Vector2(tile_center.x, tile_center.z))
		if native_projection:
			var pixels_per_meter: float = (float(batch_density[i]) if batch_ready else \
				float(view_camera.call("get_pixels_per_meter_at_position", tile_center))) * render_scale
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
	{"file": "Fern_1", "anchor": "tree", "chance": 0.55, "per": [1, 4], "ring": [0.8, 3.6], "scale": [0.6, 1.7], "biomes": ["forest", "swamp", "plains"], "range": 110.0, "max_surface_slope": 42.0, "max_surface_height": 96.0},
	{"file": "Bush_Common", "anchor": "tree", "chance": 0.3, "per": [1, 2], "ring": [1.4, 3.8], "scale": [0.8, 1.6], "biomes": ["forest", "plains", "swamp"], "range": 170.0, "max_surface_slope": 35.0, "max_surface_height": 96.0},
	{"file": "Plant_1_Big", "anchor": "tree", "chance": 0.08, "per": [1, 1], "ring": [1.0, 3.0], "scale": [0.8, 1.2], "biomes": ["forest", "swamp"], "range": 130.0, "max_surface_slope": 40.0, "max_surface_height": 96.0},
	{"file": "Mushroom_Common", "anchor": "tree", "chance": 0.22, "per": [1, 3], "ring": [0.5, 1.6], "scale": [0.7, 1.6], "biomes": ["forest", "swamp"], "range": 70.0, "max_surface_slope": 42.0, "max_surface_height": 100.0},
	{"file": "Mushroom_Laetiporus", "anchor": "tree", "chance": 0.08, "per": [1, 2], "ring": [0.4, 1.0], "scale": [0.8, 1.4], "biomes": ["forest", "swamp"], "range": 70.0, "max_surface_slope": 42.0, "max_surface_height": 100.0},
	{"file": "Pebble_Round_1", "anchor": "rock", "chance": 0.8, "per": [2, 6], "ring": [0.9, 2.8], "scale": [0.4, 2.2], "biomes": ["forest", "plains", "beach", "mountain", "swamp"], "range": 80.0, "max_surface_tilt": 35.0},
	{"file": "Pebble_Square_2", "anchor": "rock", "chance": 0.5, "per": [1, 3], "ring": [1.0, 3.0], "scale": [0.6, 1.8], "biomes": ["plains", "beach", "mountain"], "range": 80.0, "max_surface_tilt": 35.0},
	{"file": "Flower_3_Group", "anchor": "meadow", "chance": 1.0, "per": [10, 18], "ring": [0.0, 4.5], "scale": [0.8, 1.3], "biomes": ["plains", "forest"], "range": 95.0, "max_surface_slope": 30.0, "max_surface_height": 92.0},
	{"file": "Flower_4_Group", "anchor": "meadow", "chance": 0.8, "per": [8, 14], "ring": [0.0, 4.0], "scale": [0.8, 1.3], "biomes": ["plains"], "range": 95.0, "max_surface_slope": 30.0, "max_surface_height": 92.0},
	{"file": "Flower_3_Single", "anchor": "meadow", "chance": 1.0, "per": [8, 14], "ring": [1.5, 6.5], "scale": [0.8, 1.4], "biomes": ["plains", "forest", "beach"], "range": 70.0, "max_surface_slope": 30.0, "max_surface_height": 92.0},
	{"file": "Flower_4_Single", "anchor": "meadow", "chance": 0.8, "per": [6, 12], "ring": [1.5, 6.5], "scale": [0.8, 1.4], "biomes": ["plains"], "range": 70.0, "max_surface_slope": 30.0, "max_surface_height": 92.0},
	{"file": "Bush_Common_Flowers", "anchor": "meadow", "chance": 0.6, "per": [1, 2], "ring": [4.0, 7.0], "scale": [0.8, 1.4], "biomes": ["forest", "plains"], "range": 170.0, "max_surface_slope": 35.0, "max_surface_height": 96.0},
	{"file": "Grass_Wispy_Tall", "anchor": "meadow", "chance": 0.7, "per": [4, 8], "ring": [3.0, 7.5], "scale": [0.8, 2.0], "biomes": ["plains", "swamp", "beach"], "range": 95.0, "max_surface_slope": 38.0, "max_surface_height": 96.0},
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
			if _world.is_water(at.x, at.y) or not (_world.biome_at(at.x, at.y) in entry["biomes"]):
				continue
			spots.append(at)
	# All seeded candidate draws are complete before the native batch
	# corridor filter. The old strict road boundary remains unchanged and
	# no other chunk categories or authoritative game systems are affected.
	return SceneryBatches.filter_cosmetic_spots_outside_roads(
		spots, road_pieces, road_clear)


func _build_decor(origin: Vector2, rng: RandomNumberGenerator, data: Dictionary) -> void:
	if _raw_heights.size() == SAMPLES * SAMPLES and _biome_names.size() == BIOME_TEXELS * BIOME_TEXELS:
		_grass_source = GrassField.Source.new(origin, _raw_heights, SAMPLES, _biome_names, BIOME_TEXELS, _road_data, _patches)
		# Objects of neighbouring chunks can overhang this one (a house on the border).
		var chunk_rect := Rect2(origin, Vector2.ONE * Defs.CHUNK_SIZE)
		var here_cell := WorldGen.cell_of(origin.x + 1.0, origin.y + 1.0)
		var prints := PackedVector3Array()
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var source_data: Dictionary = data if dx == 0 and dz == 0 else _world.chunk(Vector2i(here_cell.x + dx, here_cell.y + dz))
				for f in GrassField.footprints(source_data):
					if chunk_rect.grow(f.z).has_point(Vector2(f.x, f.y)):
						prints.append(f)
		_grass_source.clear = prints
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
	_decor_origin = origin
	_decor_rng = rng
	_decor_anchors = anchors
	_decor_road_pieces = road_pieces
	_decor_road_clear = road_clear
	_decor_tasks.clear()
	_decor_next = 0
	if _use_nature:
		for entry in DECOR:
			if str(entry["file"]).begins_with("Pebble"):
				continue # Replaced by server-authoritative pickup stone instances.
			_decor_tasks.append({"type": "nature", "entry": entry})
	for entry in ModelCatalog.available("decor", ModelCatalog.DECOR_EXTRA):
		if SolidScenery.is_promoted_path(str(entry["path"])):
			continue # Fallen wood now has shared collision, harvest IDs and save state.
		if StoneResources.is_loose_stone_entry(entry):
			continue # No inert stone meshes; all loose stones are resource nodes.
		_decor_tasks.append({"type": "extra", "entry": entry})
	if not _decor_tasks.is_empty():
		_decor_pending.append(weakref(self))
		set_process(true)


## Called once by native WorldStreamer upon chunk adoption. Loaded world
## objects are authoritative already; cosmetics can still be in flight.
func has_pending_visual_detail() -> bool:
	return _decor_next < _decor_tasks.size()


## Builds one visual category each time the frame scheduler grants a turn.
## Interactive loot, vegetation gathering, buildings, and terrain are instant.
func _build_next_decor_entry() -> void:
	if _decor_next >= _decor_tasks.size():
		return
	var task: Dictionary = _decor_tasks[_decor_next]
	_decor_next += 1
	if str(task["type"]) == "nature":
		_build_nature_decor_entry(task["entry"])
	else:
		_build_extra_decor_entry(task["entry"])
	if _decor_next >= _decor_tasks.size():
		_finalize_hlod_stones()
		var streamer := get_parent() as WorldStreamer
		if streamer != null:
			streamer.mark_visual_details_ready(Vector3i(cell.x, 0, cell.y))
		_decor_tasks.clear()
		_decor_rng = null
		_decor_anchors.clear()
		_decor_road_pieces.clear()


func _build_nature_decor_entry(entry: Dictionary) -> void:
	var origin: Vector2 = _decor_origin
	var rng: RandomNumberGenerator = _decor_rng
	var anchors: Dictionary = _decor_anchors
	var road_pieces: Array = _decor_road_pieces
	var road_clear: float = _decor_road_clear
	var file := String(entry["file"])
	var tint_plant: bool = SceneryBatches.colorful_plant(file)
	var mesh: Mesh = Foliage.swayed(Assets.nature_mesh(file), "decor:" + file,
		0.0 if file.begins_with("Pebble") or file.begins_with("Petal")
		else (0.2 if file.begins_with("Grass") else 0.12),
		tint_plant)
	if mesh == null:
		return
	var places: Array = _anchored_spots(entry, anchors[str(entry["anchor"])], origin, rng, road_pieces, road_clear)
	if places.is_empty():
		return
	var transforms: Array[Transform3D] = []
	for i in places.size():
		var at: Vector2 = places[i]
		var size := rng.randf_range(float(entry["scale"][0]), float(entry["scale"][1]))
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size)
		transforms.append(Transform3D(basis, Vector3(at.x - origin.x, _world.height_at(at.x, at.y) - 0.02, at.y - origin.y)))
	# Unreal PCG normal-to-density/slope filter: sample true terrain normals
	# only for flora with an explicit slope policy. All transforms and seeded
	# random draws are complete before rejecting any candidate. The shared
	# native selector is pure-data; stock Godot uses the same deterministic
	# policy. This does not alter gameplay vegetation or server spawns.
	if entry.has("max_surface_slope"):
		var surface_normals := PackedVector3Array()
		for transform in transforms:
			var world_at := origin + Vector2(transform.origin.x, transform.origin.z)
			surface_normals.append(_world.normal_at(world_at.x, world_at.y))
		transforms = SceneryBatches.filter_cosmetic_transforms_surface(
			transforms, surface_normals, 0.0,
			float(entry["max_surface_slope"]), -10000000.0,
			float(entry.get("max_surface_height", 10000000.0)))
	# Unreal PCG-inspired surface-spacing filter for visual clutter only.
	# Transform generation (including seeded RNG draws) happens above, before
	# thinning, so streamed chunks keep all later seeded categories unchanged.
	# Gatherables, collisions, landmarks and server zombie spawns are untouched.
	if file.begins_with("Bush"):
		# Cliff ledges use height-aware, scale-dependent 3D PCG pruning.
		# Large bushes reserve more room; separate terraces remain populated.
		transforms = SceneryBatches.thin_cosmetic_transforms_3d(transforms, 1.6)
	elif file.begins_with("Pebble"):
		# Surface debris keeps planar spacing, now accounting for each pebble's randomized scale.
		transforms = SceneryBatches.thin_cosmetic_transforms_scaled(transforms, 0.75)
	# Unreal-style AlignToNormal for small visual rocks. Sample normals only
	# after scale-aware spacing, reducing terrain queries on dense scree.
	# All seeded transforms are generated before alignment; no additional RNG
	# draws, interactive resources or server-authoritative objects are touched.
	if entry.has("max_surface_tilt") and not transforms.is_empty():
		var alignment_normals := PackedVector3Array()
		for transform in transforms:
			var point := origin + Vector2(transform.origin.x, transform.origin.z)
			alignment_normals.append(_world.normal_at(point.x, point.y))
		transforms = SceneryBatches.align_cosmetic_transforms_surface(
			transforms, alignment_normals, float(entry["max_surface_tilt"]))
	# Only small cosmetic plants use density scaling. Pebbles, large bushes,
	# mushrooms and gatherable vegetation retain their full visual presence.
	var density_scalable: bool = file.begins_with("Flower") or \
		file.begins_with("Grass") or file.begins_with("Fern") or \
		file.begins_with("Petal")
	# Dense vegetation is split into camera-cullable cells, sparse props remain one draw call.
	for decor_batch in SceneryBatches.add(self, mesh, transforms,
			float(entry["range"]), file.begins_with("Bush"), 8.0,
			tint_plant, origin, density_scalable):
		register_scenery(decor_batch, "decor:" + file, float(entry["range"]))
		if density_scalable:
			_density_scenery_batches.append(decor_batch)
			_density_lod_elapsed = DENSITY_LOD_INTERVAL
		if file.begins_with("Bush"):
			_shadow_casters.append({"node": decor_batch, "role": "bush", "bounds": decor_batch.custom_aabb})
		if file.begins_with("Pebble"):
			_hlod_stone_sources.append(decor_batch)
	if file.begins_with("Bush"):
		# Billboard LOD: past the real mesh range, bushes continue as baked impostors.
		Rendering.impostor_field_add(self, mesh, transforms, float(entry["range"]))
	# Store only the decorative geometry actually emitted (after spacing/
	# terrain alignment). Two rock categories can share one far proxy draw.
	if file.begins_with("Pebble") and not _hlod_stone_overflow:
		if _hlod_stone_transforms.size() + transforms.size() > \
				SceneryHlodProxy.MAX_INPUT_INSTANCES:
			_hlod_stone_overflow = true
			_hlod_stone_transforms.clear()
			_hlod_stone_centers.clear()
			_hlod_stone_extents.clear()
		else:
			var stone_bounds: AABB = mesh.get_aabb()
			var half_extents: Vector3 = stone_bounds.size * 0.5
			half_extents = Vector3(maxf(0.02, half_extents.x),
				maxf(0.02, half_extents.y), maxf(0.02, half_extents.z))
			for transform in transforms:
				_hlod_stone_transforms.append(transform)
				_hlod_stone_centers.append(stone_bounds.get_center())
				_hlod_stone_extents.append(half_extents)

func _build_extra_decor_entry(entry: Dictionary) -> void:
	var origin: Vector2 = _decor_origin
	var rng: RandomNumberGenerator = _decor_rng
	var anchors: Dictionary = _decor_anchors
	var road_pieces: Array = _decor_road_pieces
	var road_clear: float = _decor_road_clear
	var extra_mesh: Mesh = ModelCatalog.entry_mesh(entry)
	if extra_mesh == null:
		return
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
		return
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
## Damage tint only changes for currently struck, streamed instances.
## No duplicate meshes and no whole-chunk GPU buffer upload on every frame.
func apply_resource_damage(hits: Dictionary) -> void:
	for node_id in _resource_colored_hits.keys():
		if hits.has(node_id):
			continue
		var previous: Dictionary = _resource_damage_slots.get(node_id, {})
		if not previous.is_empty():
			var mesh: MultiMesh = previous["mesh"]
			mesh.set_instance_color(int(previous["slot"]), previous["tint"])
		_resource_colored_hits.erase(node_id)
	for node_id in hits:
		if not _resource_damage_slots.has(node_id):
			continue
		var applied: int = int(hits[node_id])
		if int(_resource_colored_hits.get(node_id, -1)) == applied:
			continue
		var source: Dictionary = _resource_damage_slots[node_id]
		var amount: float = clampf(float(applied) / float(maxi(1, int(source["total"]))), 0.0, 1.0)
		var original: Color = source["tint"]
		var cracked: Color = original.lerp(Color(0.30, 0.27, 0.23), amount * 0.65)
		var multimesh: MultiMesh = source["mesh"]
		multimesh.set_instance_color(int(source["slot"]), cracked)
		_resource_colored_hits[node_id] = applied


func apply_state(hidden_ids: Dictionary) -> void:
	var changed := false
	_state_seen_pending = true
	for kind in _groups:
		var group: Dictionary = _groups[kind]
		var slots := PackedInt32Array()
		var transforms: Array[Transform3D] = []
		var changed_ids: Dictionary = {}
		for id in group["index"]:
			var should_hide: bool = hidden_ids.has(id)
			if should_hide == _hidden.has(id):
				continue
			var slot: int = group["index"][id]
			var original: Transform3D = group["transforms"][slot]
			slots.append(slot)
			transforms.append(Transform3D(Basis().scaled(Vector3.ONE * 0.001), original.origin)
				if should_hide else original)
			# A tree felled while you watch topples instead of vanishing (not on the first sync).
			if should_hide and _state_seen and bool(group.get("tree", false)):
				_fell_tree(group["multimesh"].mesh, original)
			changed_ids[id] = should_hide
		if slots.is_empty():
			continue
		# One native scripting call per changed chunk MultiMesh, not one
		# call per resource. Stock Godot uses an equally safe fallback.
		if not ResourceMultiMeshUpdates.apply(group["multimesh"], slots, transforms):
			push_warning("Cannot apply resource state batch for: %s" % str(kind))
			continue
		# Only commit server ID visibility cache after the renderer accepted
		# this group. Keep successful groups independent of failed groups.
		for id in changed_ids:
			if changed_ids[id]:
				_hidden[id] = true
			else:
				_hidden.erase(id)
		changed = true
	if changed and _terrain != null:
		_refresh_ground_contact()


# --- Rivers, lakes and bridges (world_rivers.gd / world_roads.gd) -----------------------------------------

static var _river_material: ShaderMaterial
static var _bridge_wood: StandardMaterial3D


static func _river_material_get() -> ShaderMaterial:
	if _river_material == null:
		_river_material = ShaderMaterial.new()
		_river_material.shader = load("res://assets/shaders/water.gdshader")
	return _river_material


## River surfaces as spline ribbons (clipped to this chunk by their segments), lakes as discs,
## and timber bridges where roads cross. Water uses the same shader as the sea.
func _build_rivers_and_bridges(origin: Vector2) -> void:
	if _world.rivers == null:
		return
	var segments: Array = _world.rivers.segments_in_cell(cell)
	if not segments.is_empty():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for seg in segments:
			var a: Vector2 = seg["a"]
			var b: Vector2 = seg["b"]
			var dir: Vector2 = (b - a).normalized()
			var side := Vector2(-dir.y, dir.x)
			var wa: float = float(seg["w0"]) + 0.6
			var wb: float = float(seg["w1"]) + 0.6
			# Extend a little along the flow so consecutive pieces overlap without gaps.
			var a2: Vector2 = a - dir * 0.8
			var b2: Vector2 = b + dir * 0.8
			var corners := [
				Vector3(a2.x + side.x * wa - origin.x, float(seg["s0"]) - 0.05, a2.y + side.y * wa - origin.y),
				Vector3(a2.x - side.x * wa - origin.x, float(seg["s0"]) - 0.05, a2.y - side.y * wa - origin.y),
				Vector3(b2.x + side.x * wb - origin.x, float(seg["s1"]) - 0.05, b2.y + side.y * wb - origin.y),
				Vector3(b2.x - side.x * wb - origin.x, float(seg["s1"]) - 0.05, b2.y - side.y * wb - origin.y),
			]
			for index in [0, 1, 2, 1, 3, 2]:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(corners[index].x, corners[index].z) * 0.1)
				st.add_vertex(corners[index])
		var river := MeshInstance3D.new()
		river.name = "River"
		river.mesh = st.commit()
		river.material_override = _river_material_get()
		river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(river)
	for lake in _world.rivers.lakes_in_cell(cell):
		# Each lake is drawn once, by the chunk holding its centre.
		if WorldGen.cell_of(float(lake["x"]), float(lake["z"])) != cell:
			continue
		var disc := MeshInstance3D.new()
		disc.name = "Lake"
		var shape := CylinderMesh.new()
		shape.top_radius = float(lake["radius"]) + 1.0
		shape.bottom_radius = shape.top_radius
		shape.height = 0.02
		shape.radial_segments = 48
		shape.rings = 1
		disc.mesh = shape
		disc.material_override = _river_material_get()
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		disc.position = Vector3(float(lake["x"]) - origin.x, float(lake["surface"]) - 0.06, float(lake["z"]) - origin.y)
		add_child(disc)
	for bridge in _world.roads.bridges_in_cell(cell):
		var a: Vector2 = bridge["a"]
		if WorldGen.cell_of(a.x, a.y) != cell:
			continue # Built once, by the chunk at its first end.
		_build_bridge(bridge, origin)


## A timber bridge: planks across an arched deck, side beams and posts down into the water.
func _build_bridge(bridge: Dictionary, origin: Vector2) -> void:
	if _bridge_wood == null:
		_bridge_wood = StandardMaterial3D.new()
		_bridge_wood.albedo_color = Color(0.42, 0.3, 0.19)
		_bridge_wood.roughness = 0.9
	var a: Vector2 = bridge["a"]
	var b: Vector2 = bridge["b"]
	var length: float = a.distance_to(b)
	var dir: Vector2 = (b - a) / maxf(length, 0.01)
	var side := Vector2(-dir.y, dir.x)
	var yaw: float = atan2(dir.x, dir.y)
	var root := Node3D.new()
	root.name = "Bridge"
	add_child(root)
	var plank_mesh := BoxMesh.new()
	plank_mesh.size = Vector3(WorldRoads.BRIDGE_HALF_WIDTH * 2.0, 0.12, 0.42)
	var planks := MultiMeshInstance3D.new()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = plank_mesh
	var count: int = maxi(int(length / 0.46), 2)
	multimesh.instance_count = count
	for k in count:
		var t: float = (float(k) + 0.5) / float(count)
		var p: Vector2 = a.lerp(b, t)
		var y: float = WorldRoads.deck_height(bridge, t) - 0.06
		var slope: float = (WorldRoads.deck_height(bridge, minf(t + 0.01, 1.0)) - WorldRoads.deck_height(bridge, maxf(t - 0.01, 0.0))) / maxf(length * 0.02, 0.001)
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -atan(slope))
		multimesh.set_instance_transform(k, Transform3D(basis.scaled(Vector3(1.0 + 0.04 * sin(k * 2.3), 1.0, 1.0)), Vector3(p.x - origin.x, y, p.y - origin.y)))
	planks.multimesh = multimesh
	planks.material_override = _bridge_wood
	root.add_child(planks)
	# Side beams (railing) and posts down to the riverbed.
	var segments := 10
	for s in [-1.0, 1.0]:
		for k in segments:
			var t0: float = float(k) / float(segments)
			var t1: float = float(k + 1) / float(segments)
			var p0: Vector2 = a.lerp(b, t0) + side * (WorldRoads.BRIDGE_HALF_WIDTH - 0.1) * s
			var p1: Vector2 = a.lerp(b, t1) + side * (WorldRoads.BRIDGE_HALF_WIDTH - 0.1) * s
			var q0 := Vector3(p0.x - origin.x, WorldRoads.deck_height(bridge, t0) + 0.85, p0.y - origin.y)
			var q1 := Vector3(p1.x - origin.x, WorldRoads.deck_height(bridge, t1) + 0.85, p1.y - origin.y)
			var rail := MeshInstance3D.new()
			var beam := BoxMesh.new()
			beam.size = Vector3(0.12, 0.12, q0.distance_to(q1) + 0.05)
			rail.mesh = beam
			rail.material_override = _bridge_wood
			rail.transform = Transform3D(Basis.looking_at(q1 - q0, Vector3.UP), (q0 + q1) * 0.5)
			root.add_child(rail)
			if k % 2 == 0:
				var post := MeshInstance3D.new()
				var post_mesh := BoxMesh.new()
				var bottom: float = _world.ground_at(p0.x, p0.y) - 0.3
				post_mesh.size = Vector3(0.16, maxf(q0.y - bottom, 0.5), 0.16)
				post.mesh = post_mesh
				post.material_override = _bridge_wood
				post.position = Vector3(q0.x, (q0.y + bottom) * 0.5, q0.z)
				root.add_child(post)


# --- Vegetation physics: trees shake when struck and topple when felled ---------------------------------

var _state_seen := false
var _state_seen_pending := false
var _shaking: Dictionary = {} # node id -> {"group", "slot", "t"}
var _resource_damage_slots: Dictionary = {} # Node id -> GPU instance, base tint and hit total.
var _resource_colored_hits: Dictionary = {} # Only modified slots, not all world nodes.
var _falling: Array = [] # [{"node": MeshInstance3D, "base": Transform3D, "axis": Vector3, "t": float}]
const SHAKE_SECONDS := 0.45
const FALL_SECONDS := 1.9
const SINK_SECONDS := 2.5


## An axe (or a fist) landed on this tree: it shudders around its base.
func shake(node_id: int) -> void:
	for kind in _groups:
		var group: Dictionary = _groups[kind]
		if bool(group.get("tree", false)) and group["index"].has(node_id) and not _hidden.has(node_id):
			_shaking[node_id] = {"group": group, "slot": int(group["index"][node_id]), "t": 0.0}
			return


func _fell_tree(mesh: Mesh, original: Transform3D) -> void:
	if mesh == null or _falling.size() >= 6:
		return
	var log := MeshInstance3D.new()
	log.mesh = mesh
	add_child(log)
	log.transform = original
	var angle: float = float(WorldGen.mix(int(original.origin.x * 10.0), int(original.origin.z * 10.0), 41) % 628) / 100.0
	var axis := Vector3(cos(angle), 0.0, sin(angle))
	_falling.append({"node": log, "base": original, "axis": axis, "t": 0.0})


func _animate_vegetation(delta: float) -> void:
	if _state_seen_pending:
		_state_seen = true
	for id in _shaking.keys():
		var entry: Dictionary = _shaking[id]
		entry["t"] = float(entry["t"]) + delta
		var group: Dictionary = entry["group"]
		var original: Transform3D = group["transforms"][int(entry["slot"])]
		var k: float = float(entry["t"]) / SHAKE_SECONDS
		if k >= 1.0 or _hidden.has(id):
			group["multimesh"].set_instance_transform(int(entry["slot"]), original)
			_shaking.erase(id)
			continue
		var sway: float = sin(k * TAU * 2.5) * (1.0 - k) * 0.06
		var basis: Basis = Basis(Vector3(1, 0, 0.3).normalized(), sway) * original.basis
		group["multimesh"].set_instance_transform(int(entry["slot"]), Transform3D(basis, original.origin))
	for i in range(_falling.size() - 1, -1, -1):
		var fall: Dictionary = _falling[i]
		fall["t"] = float(fall["t"]) + delta
		var t: float = fall["t"]
		var node: MeshInstance3D = fall["node"]
		var base: Transform3D = fall["base"]
		# Gravity-like ease-in to horizontal, a small bounce when it hits, then it sinks away.
		var k: float = clampf(t / FALL_SECONDS, 0.0, 1.0)
		var tilt: float = (PI * 0.5 - 0.06) * k * k
		if k >= 1.0:
			tilt += sin(clampf((t - FALL_SECONDS) / 0.35, 0.0, 1.0) * PI) * 0.06
		var sink: float = maxf(t - FALL_SECONDS - 0.6, 0.0) / SINK_SECONDS
		node.transform = Transform3D(Basis(fall["axis"], tilt) * base.basis, base.origin - Vector3(0.0, sink * 1.6, 0.0))
		if sink >= 1.0:
			node.queue_free()
			_falling.remove_at(i)


# --- Data Layers (data_layers.gd): content switched on and off for the whole server ---------------------

static var active_layers: Array = [] # Set by the client from the server's list; new chunks read it.
var _layer_sites: Array = []
var _layer_nodes: Dictionary = {} # layer -> Node3D


func set_data_layers(layers: Array) -> void:
	for layer in _layer_nodes.keys():
		if not layers.has(layer):
			_layer_nodes[layer].queue_free()
			_layer_nodes.erase(layer)
	if layers.has("festival") and not _layer_nodes.has("festival"):
		var node := _build_festival()
		if node != null:
			_layer_nodes["festival"] = node


## Harvest festival: strings of lanterns on posts around each settlement or camp centre in this
## chunk, and piles of pumpkins. A couple of real lights per site, the rest glow by emission.
func _build_festival() -> Node3D:
	var origin := WorldGen.cell_origin(cell)
	var root := Node3D.new()
	root.name = "LayerFestival"
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.62, 0.22)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.55, 0.18)
	glow.emission_energy_multiplier = 2.2
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.22, 0.14)
	var pumpkin_mat := StandardMaterial3D.new()
	pumpkin_mat.albedo_color = Color(0.92, 0.45, 0.08)
	pumpkin_mat.roughness = 0.6
	var placed := 0
	for site in _layer_sites:
		if not ["village", "camp", "farm", "city", "outpost", "dock"].has(str(site.get("kind", ""))):
			continue
		var centre := Vector2(float(site["x"]), float(site["z"]))
		if WorldGen.cell_of(centre.x, centre.y) != cell:
			continue # Each site is decorated once, by the chunk holding its centre.
		var radius: float = clampf(float(site.get("radius", 20.0)) * 0.45, 7.0, 18.0)
		var posts := 8
		for k in posts:
			var angle: float = TAU * float(k) / float(posts)
			var at: Vector2 = centre + Vector2.from_angle(angle) * radius
			var ground: float = _world.height_at(at.x, at.y)
			var post := MeshInstance3D.new()
			var pole := CylinderMesh.new()
			pole.top_radius = 0.05
			pole.bottom_radius = 0.06
			pole.height = 2.4
			post.mesh = pole
			post.material_override = wood
			post.position = Vector3(at.x - origin.x, ground + 1.2, at.y - origin.y)
			root.add_child(post)
			var lantern := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.22, 0.3, 0.22)
			lantern.mesh = box
			lantern.material_override = glow
			lantern.position = post.position + Vector3(0, 1.3, 0)
			root.add_child(lantern)
			if k % 4 == 0:
				var light := OmniLight3D.new()
				light.light_color = Color(1.0, 0.6, 0.25)
				light.light_energy = 1.4
				light.omni_range = 9.0
				light.shadow_enabled = false
				light.position = lantern.position
				root.add_child(light)
			# Pumpkins at the foot of every other post.
			if k % 2 == 1:
				for p in 3:
					var pumpkin := MeshInstance3D.new()
					var sphere := SphereMesh.new()
					var size: float = 0.22 + 0.08 * float(p)
					sphere.radius = size
					sphere.height = size * 1.4
					pumpkin.mesh = sphere
					pumpkin.material_override = pumpkin_mat
					var offset := Vector2.from_angle(angle + 0.6 * float(p)) * 0.55
					pumpkin.position = Vector3(at.x + offset.x - origin.x, _world.height_at(at.x + offset.x, at.y + offset.y) + size * 0.55, at.y + offset.y - origin.y)
					root.add_child(pumpkin)
		placed += 1
	if placed == 0:
		root.free()
		return null
	add_child(root)
	return root
