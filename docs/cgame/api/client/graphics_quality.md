# graphics_quality.gd

> (no header comment)

`res://scripts/client/graphics_quality.gd`

## Constants

- `const GroundPlants = preload("res://scripts/client/ground_plants.gd")`
- `const SETTINGS_PATH := "user://albion_after_graphics.cfg"`
- `const NAMES := ["Performance", "Balanced", "High", "Ultra"]`
- `const VisualProfiles = preload("res://scripts/client/graphics_profiles.gd")`
- `const GraphicsLighting = preload("res://scripts/client/graphics_lighting.gd")`
- `const GraphicsTonemapping = preload("res://scripts/client/graphics_tonemapping.gd")`
- `const GraphicsLens = preload("res://scripts/client/graphics_lens.gd")`
- `const GraphicsShadowAtlas = preload("res://scripts/client/graphics_shadow_atlas.gd")`
- `const GraphicsContactShadows = preload("res://scripts/client/graphics_contact_shadows.gd")`
- `const GraphicsSunShafts = preload("res://scripts/client/graphics_sun_shafts.gd")`
- `const BlobShadow = preload("res://scripts/client/blob_shadow.gd")`
- `const LensDirt = preload("res://scripts/client/lens_dirt.gd")`
- `const GraphicsReflections = preload("res://scripts/client/graphics_reflections.gd")`
- `const GraphicsIndirectLighting = preload("res://scripts/client/graphics_indirect_lighting.gd")`
- `const WaterRefraction = preload("res://scripts/client/water_refraction.gd")`
- `const WaterCaustics = preload("res://scripts/client/water_caustics.gd")`
- `const GraphicsResolution = preload("res://scripts/client/graphics_resolution.gd")`
- `const GraphicsTextureStreaming = preload("res://scripts/client/graphics_texture_streaming.gd")`
- `const GraphicsNativeSpecularAA = preload("res://scripts/client/graphics_native_specular_aa.gd")`
- `const GraphicsSkinShading = preload("res://scripts/client/graphics_skin_scattering.gd")`
- `const StoneMicrodetail = preload("res://scripts/client/graphics_stone_microdetail.gd")`
- `const ShadowBudget = preload("res://scripts/client/shadow_budget.gd")`
- `const Foliage = preload("res://scripts/client/foliage.gd")`
- `const SceneryLod = preload("res://scripts/client/scenery_lod.gd")`
- `const DungeonLightBudget = preload("res://scripts/client/dungeon_light_budget.gd")`
- `const DungeonReflectionBudget = preload("res://scripts/client/dungeon_reflection_budget.gd")`
- `const OutdoorReflectionBudget = preload("res://scripts/client/outdoor_reflection_budget.gd")`
- `const ChunkView = preload("res://scripts/client/chunk_view.gd")`
- `const GraphicsFramePacing = preload("res://scripts/client/graphics_frame_pacing.gd")`
- `const GraphicsFoveatedShading = preload("res://scripts/client/graphics_foveated_shading.gd")`
- `const GraphicsHdrOutput = preload("res://scripts/client/graphics_hdr_output.gd")`
- `const GraphicsAreaLights = preload("res://scripts/client/graphics_area_lights.gd")`
- `const CharacterShading = preload("res://scripts/client/character_shading.gd")`
- `const ImpostorField = preload("res://scripts/client/impostor_field.gd")`

## Functions

### `load_preference`

```gdscript
static func load_preference() -> void
```

### `level`

```gdscript
static func level() -> int
```

### `unload_budget_for_quality`

```gdscript
static func unload_budget_for_quality(value: int) -> int
```

Per-refresh limit for releasing old *visual* chunks after teleports.
High quality can tolerate more teardown work per streaming tick; lower
presets pace detach/cleanup more aggressively to avoid frame spikes.

### `unload_time_budget_for_quality`

```gdscript
static func unload_time_budget_for_quality(value: int) -> int
```

Soft wall-clock time slice for native obsolete-chunk deactivation.
Keep a small guaranteed cleanup slice even on Performance settings.

### `streamed_chunk_cache_bytes_for_quality`

```gdscript
static func streamed_chunk_cache_bytes_for_quality(value: int) -> int
```

Conservative detached cosmetic scene cache estimate, not physical RAM.

### `streamed_chunk_cache_retention_for_quality`

```gdscript
static func streamed_chunk_cache_retention_for_quality(value: int) -> float
```

Bound how long detached scenery retains memory while player is idle.

### `streamed_cache_expirations_for_quality`

```gdscript
static func streamed_cache_expirations_for_quality(value: int) -> int
```

Time-slice ordinary expiration of detached cosmetic chunks.

### `streamed_cache_expiration_usec_for_quality`

```gdscript
static func streamed_cache_expiration_usec_for_quality(value: int) -> int
```

### `startup_streaming_area_for_quality`

```gdscript
static func startup_streaming_area_for_quality(value: int) -> float
```

Startup only: Unreal World Partition-style area ramp. Preserve a safe
nearby terrain area and gradually request the configured full range.
Fractions scale area, not distance, on our 2D XZ streaming grid.

### `startup_streaming_ramp_duration`

```gdscript
static func startup_streaming_ramp_duration(value: int) -> float
```

### `streamed_tick_radius_for_quality`

```gdscript
static func streamed_tick_radius_for_quality(value: int) -> float
```

Cosmetic streaming only: scripts far from the camera update at a
budgeted interval instead of running expensive visual work every frame.
This is separate from the even farther complete simulation-pause radius.

### `streamed_tick_interval_for_quality`

```gdscript
static func streamed_tick_interval_for_quality(value: int) -> float
```

### `get_name`

```gdscript
static func get_name() -> String
```

### `set_level`

```gdscript
static func set_level(value: int, persist: bool = true) -> void
```

### `cycle`

```gdscript
static func cycle() -> void
```

### `profile`

```gdscript
static func profile(value: int) -> Dictionary
```

Pure data so settings can be verified without a GPU and retuned together.

### `update_dynamic_sdfgi`

```gdscript
static func update_dynamic_sdfgi(environment: Environment, underground: bool) -> void
```

Limit expensive SDFGI occlusion to Ultra dungeon spaces. Online scene
calls this at its existing weather tick, with idempotent GPU updates.

### `post_sharpen_strength`

```gdscript
static func post_sharpen_strength(value: int, method: String, adaptive: bool) -> float
```

Native manual High/Ultra can use a small focused detail boost. Forward+ adaptive
FSR2 already performs image reconstruction; never sharpen that output twice.

### `metalfx_resolution_floor`

```gdscript
static func metalfx_resolution_floor() -> float
```

Fast path for frame-rate adjustment; no scene-node, texture, LOD or
streamer changes are performed here.
The same driver-aware policy is used for initial, manual and adaptive
resolution changes, without relaunching or rebuilding world resources.

### `apply_resolution`

```gdscript
static func apply_resolution(viewport: Viewport, render_scale: float = -1.0, adaptive: bool = false) -> void
```

### `apply`

```gdscript
static func apply(viewport: Viewport, atmosphere: Node3D, post_material: ShaderMaterial, water: MeshInstance3D = null, streamer: Node = null, render_scale: float = -1.0, adaptive: bool = false) -> void
```

