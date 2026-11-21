# chunk_view.gd

> The visual side of one world chunk: its terrain and every tree, rock, bush and crate in it.

`res://scripts/client/chunk_view.gd`

## Overview

The visual side of one world chunk: its terrain and every tree, rock, bush and crate in it.
Nothing here is sent over the network. It is built from the seed, and only the "depleted" and
"opened" flags from the server change what is shown.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const WorldGen = preload("res://scripts/shared/world_gen.gd")`
- `const GroundPlants = preload("res://scripts/client/ground_plants.gd")`
- `const Dungeon = preload("res://scripts/shared/dungeon.gd")`
- `const Meshes = preload("res://scripts/client/meshes.gd")`
- `const Assets = preload("res://scripts/client/assets.gd")`
- `const Foliage = preload("res://scripts/client/foliage.gd")`
- `const CharacterModel = preload("res://scripts/client/character_model.gd")`
- `const ModelCatalog = preload("res://scripts/client/model_catalog.gd")`
- `const WorldRoads = preload("res://scripts/shared/world_roads.gd")`
- `const GrassField = preload("res://scripts/client/grass_field.gd")`
- `const GroundContactAO = preload("res://scripts/client/ground_contact_ao.gd")`
- `const TerrainSeamNormals = preload("res://scripts/client/terrain_seam_normals.gd")`
- `const TerrainCurvature = preload("res://scripts/client/terrain_curvature.gd")`
- `const TerrainHorizonAO = preload("res://scripts/client/terrain_horizon_ao.gd")`
- `const TerrainAnisotropy = preload("res://scripts/client/terrain_anisotropy.gd")`
- `const ObjectBatchGrid = preload("res://scripts/client/object_batch_grid.gd")`
- `const SceneryBatches = preload("res://scripts/client/scenery_batches.gd")`
- `const ImpostorField = preload("res://scripts/client/impostor_field.gd")`
- `const ResourceMultiMeshUpdates = preload("res://scripts/client/multimesh_resource_updates.gd")`
- `const ResourceInstanceInitializer = preload("res://scripts/client/resource_instance_initializer.gd")`
- `const DecorStreamingPolicy = preload("res://scripts/client/decor_streaming_policy.gd")`
- `const ShadowBudget = preload("res://scripts/client/shadow_budget.gd")`
- `const DungeonLightBudget = preload("res://scripts/client/dungeon_light_budget.gd")`
- `const DungeonReflectionBudget = preload("res://scripts/client/dungeon_reflection_budget.gd")`
- `const OutdoorReflectionBudget = preload("res://scripts/client/outdoor_reflection_budget.gd")`
- `const DungeonOcclusion = preload("res://scripts/client/dungeon_occlusion.gd")`
- `const SceneryLod = preload("res://scripts/client/scenery_lod.gd")`
- `const SceneryDensityLod = preload("res://scripts/client/scenery_density_lod.gd")`
- `const SceneryHlodProxy = preload("res://scripts/client/scenery_hlod_proxy.gd")`
- `const CampfireFx = preload("res://scripts/client/campfire_fx.gd")`
- `const SAMPLES := 33 # Heights per side: one every 2 m.`
- `const HEIGHT_MIN := -45.0`
- `const HEIGHT_RANGE := 220.0`
- `const GROUND_SHADER := """`
- `const TERRAIN_LOD_GROUP := "aa_chunked_terrain_lod"`
- `const TERRAIN_LAYERS := ["lush", "dry", "forest", "swamp", "road", "cliff", "mountain", "sand", "snow", "asphalt", "concrete", "brick", "plank"]`
- `const TERRAIN_DIR := "res://assets/textures/terrain/"`
- `const TERRAIN_PBR_DIR := "res://assets/textures/terrain_pbr/"`
- `const TERRAIN_SOURCES := {`
- `const TERRAIN_TINT_STRENGTH := 0.25`
- `const TERRAIN_TARGETS := [Color(0.24, 0.38, 0.14), Color(0.37, 0.41, 0.19), Color(0.28, 0.32, 0.15), Color(0.27, 0.29, 0.17),`
- `const SITE_PAVING := {"city": [11, 0.8], "bunker": [10, 0.75], "depot": [10, 0.6], "dock": [12, 0.65]}`
- `const BIOME_TEXELS := 17 # Biome samples per chunk side (every 4 m), shared on the borders with the neighbours.`
- `const DENSITY_LOD_INTERVAL := 0.6`
- `const GRASS_LOD_INTERVAL := 0.35 # Update a few times a second, not every render frame.`
- `const SHADOW_INTERVAL := 0.5`
- `const GRASS_GROUP := "aa_grass_tiles"` - Runtime tuning keeps the grass LOD system intact while bounding draw distance and generation spikes.
- `const TERRAIN_GROUP := "aa_textured_terrain"`
- `const SCENERY_GROUP := "aa_scenery_multimeshes"`
- `const TERRAIN_ARRAY_DIR := "res://assets/textures/terrain_arrays/"` - The textured ground material (Poly Haven layers in two texture arrays), or null when the textures are missing. Prebuilt VRAM-compressed layer arrays (tools/build_terrain_arrays.sh): 2k albedo at a 2 m tile is ~1024 texels per metre, the first-person target; built at import time instead of at startup.
- `const TREES_BY_BIOME := {`
- `const DECOR := [`
- `const MEADOWS_PER_CHUNK := 3`
- `const MEADOW_CLEARANCE := 7.0 # Metres from the nearest tree for a meadow's heart.`
- `const SHAKE_SECONDS := 0.45`
- `const FALL_SECONDS := 1.9`
- `const SINK_SECONDS := 2.5`

## Documented variables

- `var _density_scenery_batches: Array[MultiMeshInstance3D] = []` - Density-scalable decorative flowers/grass only; no gameplay nodes.
- `var _hlod_stone_sources: Array[MultiMeshInstance3D] = []` - Chunk-local cosmetic pebbles: several near MultiMesh variants share one low-poly, single-surface HLOD mesh in the distance.
- `var _streaming_simulation_active := true` - WorldStreamer only requests cosmetic simulation changes. Terrain, collision, loot, and server-authoritative entities remain resident and unchanged.
- `static var _ore_material_cache: StandardMaterial3D` - Ore is the same rock tinted like copper, so it reads as something worth mining.

## Functions

### `configure_terrain_horizon`

```gdscript
static func configure_terrain_horizon(quality: int) -> void
```

Sampler quality follows the existing graphics preset without changing any
world or texture data. New chunks use the cached shader of the chosen tier.
Expensive halo sampling is restricted to High/Ultra. Switches update
existing terrain vertices; no shader textures or new draw passes.

### `apply_terrain_horizon`

```gdscript
static func apply_terrain_horizon(node: Node) -> void
```

### `configure_terrain_mesh_budget`

```gdscript
static func configure_terrain_mesh_budget(microseconds: int) -> void
```

Like Unreal's streaming time slice, our native Godot fork amortizes
expensive uncached terrain mesh builds across process frames. The limit
is shared by all ChunkedTerrain3D nodes, not multiplied per world cell.

### `apply_terrain_mesh_budget`

```gdscript
static func apply_terrain_mesh_budget(node: Node) -> void
```

### `configure_terrain_streaming_priority`

```gdscript
static func configure_terrain_streaming_priority(mode: int) -> void
```

Prioritize filling visible terrain gaps before costly LOD upgrades.
Modes: 0=legacy order, 1=near first, 2=near + view-facing bias.

### `apply_terrain_streaming_priority`

```gdscript
static func apply_terrain_streaming_priority(node: Node) -> void
```

### `configure_terrain_geomorph`

```gdscript
static func configure_terrain_geomorph(quality: int) -> void
```

### `apply_terrain_geomorph`

```gdscript
static func apply_terrain_geomorph(node: Node) -> void
```

### `terrain_lod_distance_for_quality`

```gdscript
static func terrain_lod_distance_for_quality(quality: int) -> float
```

Screen-relative geometry thresholds for the forked ChunkedTerrain3D.
Existing and new terrain chunks use the same quality-selected budget.

### `configure_terrain_screen_lod`

```gdscript
static func configure_terrain_screen_lod(quality: int) -> void
```

### `apply_terrain_screen_lod`

```gdscript
static func apply_terrain_screen_lod(node: Node) -> void
```

### `terrain_error_strength_for_quality`

```gdscript
static func terrain_error_strength_for_quality(quality: int) -> float
```

Preserve jagged ridges at distance but simplify flat plains early.
The native engine caches height deviation once; graphics profiles only
update a weight, with no new shader passes or terrain regeneration.

### `configure_terrain_error_lod`

```gdscript
static func configure_terrain_error_lod(quality: int) -> void
```

### `apply_terrain_error_lod`

```gdscript
static func apply_terrain_error_lod(node: Node) -> void
```

### `configure_terrain_pixel_error`

```gdscript
static func configure_terrain_pixel_error(pixels: float) -> void
```

Per-chunk geometric simplification budget in screen pixels.
The same group includes PBR and procedural fallback terrain.

### `apply_terrain_pixel_error`

```gdscript
static func apply_terrain_pixel_error(terrain: Node) -> void
```

### `configure_terrain_filter`

```gdscript
static func configure_terrain_filter(quality: int) -> void
```

### `apply_terrain_filter`

```gdscript
static func apply_terrain_filter(terrain: Node) -> void
```

Existing chunks keep their road/biome maps and material parameter overrides.

### `configure_grass`

```gdscript
static func configure_grass(build_radius: float, budget_usec: int, fade_start: float, fade_end: float) -> void
```

### `configure_decor_budget`

```gdscript
static func configure_decor_budget(microseconds: int) -> void
```

Streamed instances inherit user quality; existing instances change only
when the preset changes, not each frame.
One shared budget for ALL loaded ChunkViews, not one limit per cell.

### `get_pending_decor_count`

```gdscript
static func get_pending_decor_count() -> int
```

### `configure_scenery`

```gdscript
static func configure_scenery(quality: int) -> void
```

### `apply_scenery_detail`

```gdscript
static func apply_scenery_detail(instance: MultiMeshInstance3D) -> void
```

### `register_scenery`

```gdscript
static func register_scenery(instance: MultiMeshInstance3D, kind: String, base_distance: float = 0.0) -> void
```

### `ground_material`

```gdscript
static func ground_material() -> ShaderMaterial
```

### `textured_material`

```gdscript
static func textured_material() -> ShaderMaterial
```

### `build`

```gdscript
func build(p_world, p_cell: Vector2i) -> void
```

### `set_streaming_tick_interval`

```gdscript
func set_streaming_tick_interval(seconds: float) -> void
```

Native WorldStreamer can request a reduced cosmetic tick frequency for
distant but still simulation-active chunks. Physics/network/gameplay are
not controlled by this scene. Zero restores full frame-rate processing.

### `can_cache_streaming_chunk`

```gdscript
func can_cache_streaming_chunk() -> bool
```

Only immutable client-generated scenery may use WorldStreamer's optional
bounded detached-node cache. This chunk never owns server authority.

### `get_streaming_cache_cost_bytes`

```gdscript
func get_streaming_cache_cost_bytes() -> int
```

Conservative cached-scene estimate. Shared shader/texture assets are
excluded to avoid double counting; this does not measure RAM or VRAM.

### `on_streaming_cache_restored`

```gdscript
func on_streaming_cache_restored() -> void
```

Reattached scenes never rerun _ready(). Restore deferred decor queue
membership and force grass/shadow LOD checks near the new camera position.

### `set_streaming_simulation_active`

```gdscript
func set_streaming_simulation_active(active: bool) -> void
```

### `has_pending_visual_detail`

```gdscript
func has_pending_visual_detail() -> bool
```

Called once by native WorldStreamer upon chunk adoption. Loaded world
objects are authoritative already; cosmetics can still be in flight.

### `apply_state`

```gdscript
func apply_state(hidden_ids: Dictionary) -> void
```

Hides depleted nodes and opened crates. `hidden_ids` is the set of ids the server says are gone.

### `shake`

```gdscript
func shake(node_id: int) -> void
```

An axe (or a fist) landed on this tree: it shudders around its base.

### `set_data_layers`

```gdscript
func set_data_layers(layers: Array) -> void
```

_47 private function(s) starting with `_` are not listed._
