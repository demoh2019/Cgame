# grass_field.gd

> A carpet of short grass over a whole chunk: thousands of procedural clumps (a few tapered blades each, no textures, no alpha cut-outs) in one MultiMesh, so i...

`res://scripts/client/grass_field.gd`

## Overview

A carpet of short grass over a whole chunk: thousands of procedural clumps (a few tapered blades each, no textures, no
alpha cut-outs) in one MultiMesh, so it costs one draw call. Every clump has its own tint, the wind bends the tips,
and near the edge of the view the blades sink into the ground instead of popping. Client-only: nothing blocks anyone.

## Constants

- `const WorldGen = preload("res://scripts/shared/world_gen.gd")`
- `const RoadMaskMaxFilter = preload("res://scripts/client/road_mask_max_filter.gd")`
- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const SPACING := 0.55 # Metres between tuft candidates (jittered): dense enough that the soil barely shows.`
- `const CLUMP_CELL := 3.2 # Size of the patches (Voronoi cells) that share a height and a shade.`
- `const TILE := 16.0 # Each chunk is cut into tiles of this size, so the camera only draws the tiles it sees.`
- `const FADE_START := 44.0 # Horizontal distance from the camera where the blades begin to sink, and where they are gone.`
- `const FADE_END := 60.0`
- `const LOD_BLADES := [18, 9, 4]`
- `const LOD_SWITCH_DISTANCE := [24.0, 42.0]`
- `const LOD_HYSTERESIS := 3.0`
- `const DENSITY_FIRST_START := 18.0`
- `const DENSITY_FIRST_END := 34.0`
- `const DENSITY_SECOND_START := 35.0`
- `const DENSITY_SECOND_END := 55.0`
- `const DENSITY_FIRST_DROP := 0.28`
- `const DENSITY_SECOND_DROP := 0.32`
- `const SHADER_CODE := """`
- `const BIOME_GRASS := {`
- `const BIOME_DENSITY := {"forest": 0.95, "plains": 1.0, "swamp": 0.95, "beach": 0.25, "mountain": 0.6}`
- `const SPECIES_FINE := 0` - Blade species inside one tuft (UV2.x = species / 4): fine grass, broad sedge-like leaves, tall seed stalks and low clover-like leaves. UV2.y is a per-blade random for colour.
- `const SPECIES_BROAD := 1`
- `const SPECIES_STALK := 2`
- `const SPECIES_LOW := 3`
- `const SPECIES_WISPY := 4 # Feather grass: very thin, pale, long and arching.`
- `const SPECIES_FLOWER := 5 # A stem with a flower head; the head only shows in flowering patches.`
- `const SPECIES_REED := 6 # Thick, tall, dark rush-like blade.`
- `const SPECIES_REDTOP := 7 # Bentgrass with a reddish-purple seed haze.`
- `const SPECIES_SPROUT := 8 # Short, bright lime new growth.`
- `const SPECIES_COUNT := 9.0`

## Classes

- `class Clumps:` - The grass patches (Voronoi cells of jittered centres) around a chunk, precomputed once: per cell its centre, a height roll and a shade. Real grass grows in patches that share a height and a colour; random heights per tuft look messy (Ghost of Tsushima's grass talk).
- `class Source:` - Everything one chunk's grass is grown from. The tiles are built one at a time (see ChunkView), so a chunk coming into view costs a few milliseconds per frame instead of a hitch. `heights`: samples × samples raw heights over the chunk; `biomes`: texels × texels biome names; `road`: the chunk's 1 m road mask (empty when no road crosses it); `patches`: paved sites as x, z, radius, layer.

## Functions

### `lushness`

```gdscript
static func lushness(x: float, z: float) -> float
```

0..1: how lush the ground is here. Smooth noise from fixed hashes, so every client grows the same meadows.

### `clump_mesh`

```gdscript
static func clump_mesh(blades: int = 18) -> ArrayMesh
```

One tuft: thin, curved blades of several species leaning outwards. UV.y runs from root (0) to tip (1).

### `screen_lod_scale`

```gdscript
static func screen_lod_scale(view_height: float, vertical_fov_degrees: float) -> float
```

Choose one of three blade counts using distance from a tile to the camera.
A 3 m dead zone avoids oscillating between mesh variants when the view moves.
Approximate on-screen tuft size using the camera's vertical focal length.
720p at 38 degrees is the original art-tuned reference. Clamp extreme
resolutions to avoid making 4K rendering multiply grass cost without bound.
Compatible with GL Compatibility and Forward+; no GPU query is needed.

### `projected_lod_distance`

```gdscript
static func projected_lod_distance(horizontal_distance: float, pixels_per_meter: float, focal_ratio: float) -> float
```

Convert native Camera3D pixels-per-meter into a stable grass LOD
distance. A 60% projection / 40% horizontal blend preserves the original
ground-carpet placement while fixing over-detail on zoomed-out cliffs and
under-detail on elevated terrain. Only values within the 720p reference
range may extend quality; extra resolution is capped to avoid GPU spikes.
This pure helper also works with a future orthographic camera.

### `lod_for_distance`

```gdscript
static func lod_for_distance(distance: float, previous: int = 0, range_scale: float = 1.0) -> int
```

Scaling distances is equivalent to selecting LOD by projected screen
coverage for the fixed-size grass blades. Preset fade range controls how
long foliage should stay dense; screen resolution/FOV controls sharpness.

### `needs_lod_refresh`

```gdscript
static func needs_lod_refresh(previous_eye: Vector2, previous_scale: float, previous_tile_count: int, eye: Vector2, range_scale: float, tile_count: int) -> bool
```

Avoid walking every tile when a stationary camera has not changed its
pixel budget or when grass generation has made no progress. Changes smaller
than 25 cm cannot materially affect 16-metre tile distance LOD thresholds.

### `visible_count_for_distance`

```gdscript
static func visible_count_for_distance(total: int, distance: float, range_scale: float = 1.0) -> int
```

The MultiMesh renderer draws only a prefix of each tuft buffer.
Smooth ranges let distant grass thin gradually without any mesh rebuild.
It never changes the number of gameplay entities or collision objects.

### `shuffle_instances`

```gdscript
static func shuffle_instances(buffer: PackedFloat32Array, total: int, seed: int) -> void
```

Fisher-Yates is done once during each tile's budgeted construction.
Crucial: move all 16 floats (12 transform + 4 tint) together; otherwise
fractional visible_instance_count would delete whole spatial rows.

### `material`

```gdscript
static func material() -> ShaderMaterial
```

### `footprints`

```gdscript
static func footprints(chunk_data: Dictionary) -> PackedVector3Array
```

Ground footprints (x, z, radius) of the chunk's static objects: crates, props, ruins and resource nodes.

### `under_object`

```gdscript
static func under_object(x: float, z: float, footprints_in_tile: PackedVector3Array) -> bool
```

True when a tuft at (x, z) would grow out of one of the footprints.

### `sample`

```gdscript
static func sample(source: Source, lx: float, lz: float) -> Dictionary
```

Ground facts at a chunk-local point for other ground cover (scanned plants): same rules as the grass,
so plants never grow in water, on roads, on cliffs, in the hub plaza or out of objects.

### `tile_count`

```gdscript
static func tile_count() -> int
```

### `build_tile`

```gdscript
static func build_tile(source: Source, tile: int) -> MultiMeshInstance3D
```

The grass of one 16 m tile of a chunk (one MultiMesh, one draw call), or null when nothing grows there.

_2 private function(s) starting with `_` are not listed._
