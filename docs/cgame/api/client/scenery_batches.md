# scenery_batches.gd

> Chunk-local GPU instancing with spatial culling.

`res://scripts/client/scenery_batches.gd`

## Overview

Chunk-local GPU instancing with spatial culling.
A MultiMesh is culled as a whole, not per instance: large decoration batches
unnecessarily draw all flowers when just one corner enters the view.
Subdivide only busy meshes into 32 m tiles to keep draw-call costs bounded.

## Constants

- `const SceneryDensityLod = preload("res://scripts/client/scenery_density_lod.gd")`
- `const TILE_SIZE := 32.0`
- `const SPLIT_MIN_INSTANCES := 48`
- `const MAX_SCENERY_INSTANCES := 65536`
- `const MAX_SCENERY_CLUSTERS := 256`
- `const BOUNDS_MARGIN := 0.6 # Mesh movement in wind and imprecise imported bounds.`
- `const PCG_SURFACE_MAX_CANDIDATES := 16384` - Unreal PCG-style surface normal/altitude screening for cosmetic placement. This is pure point selection, so callers may finish generating the seeded transform stream *before* applying a slope policy.
- `const PCG_SURFACE_MAX_SELECTED := 4096`
- `const PCG_SURFACE_COORD_LIMIT := 10000000.0`
- `const PCG_MAX_CANDIDATES := 16384`
- `const PCG_MAX_SELECTED := 4096`

## Documented variables

- `static var _path_corridor_native: Object = null` - Unreal PCG spline-distance-inspired batch road corridor exclusion. Roads are independent XZ segments [Vector2 start, Vector2 end], not one continuous polyline. Keep the old strict "< clearance" boundary policy. All candidate RNG and biome filtering happens upstream in ChunkView.
- `static var _pcg_native: Object = null` - Unreal PCG-style minimum-distance sampling for client-only decorations. The native filter uses a spatial hash; on older/stock engines the same greedy stable-input policy is implemented with GDScript buckets. Importantly, callers generate transforms before thinning, so the seeded RNG stream for subsequent scenery categories is unchanged.
- `static var _pcg_native_3d: Object = null` - Height-aware PCG selection for stacked cliffs/terraces. On stock Godot the fallback uses the same deterministic greedy 3D spatial hash.

## Functions

### `partition_indices_3d`

```gdscript
static func partition_indices_3d(points: PackedVector3Array, cell_size: float = TILE_SIZE, min_split_count: int = SPLIT_MIN_INSTANCES, max_clusters: int = MAX_SCENERY_CLUSTERS, prefer_native: bool = true) -> Array
```

Native module computes the index buckets; no scene objects or RNG are touched.
Use prefer_native=false to test the exact portable policy independently.

### `partition_indices_adaptive_3d`

```gdscript
static func partition_indices_adaptive_3d(points: PackedVector3Array, cell_size: float = TILE_SIZE, min_split_count: int = SPLIT_MIN_INSTANCES, max_clusters: int = MAX_SCENERY_CLUSTERS, max_coarsen_passes: int = 8, prefer_native: bool = true) -> Array
```

### `cluster_point_bounds`

```gdscript
static func cluster_point_bounds(points: PackedVector3Array, groups: Array, margin: float = 0.0, prefer_native: bool = true) -> Array
```

Bounds for already-computed index groups; original point positions are
the LOD/streaming anchors. This is NOT mesh geometry or renderer bounds.
Native C++ does an exact-cover validation; stock Godot mirrors it.

### `partition`

```gdscript
static func partition(transforms: Array[Transform3D]) -> Array
```

Native 3D spatial cells yield tighter cullable MultiMesh bounds on steep
terrain; flat ground still produces the same stable 32 m XY-plane tiles.
Every instance appears in exactly one batch, preserving its original order.

### `pcg_surface_filter_indices`

```gdscript
static func pcg_surface_filter_indices(positions: PackedVector3Array, normals: PackedVector3Array, min_slope_deg: float = 0.0, max_slope_deg: float = 90.0, min_height: float = -PCG_SURFACE_COORD_LIMIT, max_height: float = PCG_SURFACE_COORD_LIMIT, max_selected: int = PCG_SURFACE_MAX_SELECTED, prefer_native: bool = true) -> PackedInt32Array
```

Caller-owned buffers stay intact. prefer_native=false is for parity tests.

### `filter_cosmetic_transforms_surface`

```gdscript
static func filter_cosmetic_transforms_surface(transforms: Array[Transform3D], normals: PackedVector3Array, min_slope_deg: float, max_slope_deg: float, min_height: float = -PCG_SURFACE_COORD_LIMIT, max_height: float = PCG_SURFACE_COORD_LIMIT, prefer_native: bool = true) -> Array[Transform3D]
```

Returns only visual transforms whose sampled terrain surface is suitable.
Fail open on malformed inputs; real empty matches intentionally stay empty.

### `align_cosmetic_transforms_surface`

```gdscript
static func align_cosmetic_transforms_surface(transforms: Array[Transform3D], normals: PackedVector3Array, max_tilt_degrees: float = 35.0, prefer_native: bool = true) -> Array[Transform3D]
```

Returns a new array so the source transforms remain reusable. Validation
errors fail open only at this gameplay wrapper, not inside native engine API.

### `filter_cosmetic_spots_outside_roads`

```gdscript
static func filter_cosmetic_spots_outside_roads(spots: Array, road_pieces: Array, clearance: float, prefer_native: bool = true) -> Array
```

Native preprocessing avoids running the per-plant/per-road loop in GDScript.
Overlarge or malformed batches keep the original scalar policy.
No changes to road geometry, RNG, scene nodes, or authoritative resources.

### `pcg_filter_indices`

```gdscript
static func pcg_filter_indices(candidates: PackedVector2Array, min_spacing: float, max_selected: int = PCG_MAX_SELECTED, prefer_native: bool = true) -> PackedInt32Array
```

Returns original candidate indices; use prefer_native=false in parity tests.

### `pcg_filter_indices_scaled`

```gdscript
static func pcg_filter_indices_scaled(candidates: PackedVector2Array, scales: PackedFloat32Array, min_spacing: float, max_selected: int = PCG_MAX_SELECTED, largest_first: bool = true, prefer_native: bool = true) -> PackedInt32Array
```

Uses the native engine when it has the new API, otherwise identical GDScript.

### `thin_cosmetic_transforms`

```gdscript
static func thin_cosmetic_transforms(transforms: Array[Transform3D], min_spacing: float, prefer_native: bool = true) -> Array[Transform3D]
```

Runs exclusively on already built cosmetic MultiMesh transforms; does not
modify terrain, interactive resource nodes, server spawns or collisions.

### `pcg_filter_indices_3d`

```gdscript
static func pcg_filter_indices_3d(candidates: PackedVector3Array, min_spacing: float, max_selected: int = PCG_MAX_SELECTED, prefer_native: bool = true) -> PackedInt32Array
```

### `pcg_filter_indices_3d_scaled`

```gdscript
static func pcg_filter_indices_3d_scaled(points: PackedVector3Array, scales: PackedFloat32Array, spacing: float, cap: int = PCG_MAX_SELECTED, largest_first: bool = true, prefer_native: bool = true) -> PackedInt32Array
```

### `thin_cosmetic_transforms_3d`

```gdscript
static func thin_cosmetic_transforms_3d(transforms: Array[Transform3D], min_spacing: float, prefer_native: bool = true) -> Array[Transform3D]
```

Called after seeded transforms are generated, so thinning never changes
the random stream for neighboring chunks or later decoration categories.

### `thin_cosmetic_transforms_scaled`

```gdscript
static func thin_cosmetic_transforms_scaled(transforms: Array[Transform3D], min_spacing: float, prefer_native: bool = true) -> Array[Transform3D]
```

Scale-adaptive visual spacing for random-size bushes and loose pebbles.
All RNG draws and transforms are generated by ChunkView before this pass.
Clamping to [0.5, 2.0] keeps a constant local lookup footprint.

### `bounds_for`

```gdscript
static func bounds_for(mesh: Mesh, transforms: Array) -> AABB
```

Custom bounds are in the parent's local coordinates, matching MultiMesh transforms.
Include full mesh extents and rotation; using only placement centers could clip trees.

### `tint_at`

```gdscript
static func tint_at(world_xz: Vector2) -> Color
```

GPU-instanced colour: same PBR material, no per-object nodes or variants.
A coordinate-only hash is stable across chunk streaming and in any
partition order; world_origin converts local MultiMesh transforms to world.

### `packed_group`

```gdscript
static func packed_group(transforms: Array, tinted: bool = false, world_origin: Vector2 = Vector2.ZERO) -> PackedFloat32Array
```

Native RD MultiMesh data: 3x4 row-major transform (12 floats), followed
by RGBA colour (four floats) only on opted-in foliage. One GPU upload
replaces O(n) separate instance transform/colour RenderingServer calls.

### `packed_group_for`

```gdscript
static func packed_group_for(multimesh: MultiMesh, transforms: Array, tinted: bool = false, world_origin: Vector2 = Vector2.ZERO) -> PackedFloat32Array
```

Use the fork's bulk native packing when present. Unlike N*12 script
writes, Cgame marshals matrices into linear GPU-ready memory in one pass.
Stock Godot uses the unchanged original layout and seeded pigment logic.

### `bounds_for_instance`

```gdscript
static func bounds_for_instance(multimesh: MultiMesh, mesh: Mesh, transforms: Array) -> AABB
```

Correct world-space AABBs are essential: Godot culls a whole MultiMesh
cluster, never individual trees. Use native union if available.

### `colorful_plant`

```gdscript
static func colorful_plant(name: String) -> bool
```

The mesh shader must opt in to using the instance COLOR attribute.
Only leaves/flowers/grass/ferns/green plants have this enabled in
ChunkView. Rocks, buildings, mushrooms and original PBR art are unchanged.

### `add`

```gdscript
static func add(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D], draw_distance: float, cast_shadows: bool = false, fade_margin: float = 8.0, tint_variation: bool = false, world_origin: Vector2 = Vector2.ZERO, density_scalable: bool = false) -> Array[MultiMeshInstance3D]
```

Visual-only props: instancing stays on the GPU and no physics/server nodes are made.

_11 private function(s) starting with `_` are not listed._
