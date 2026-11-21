# scenery_lod.gd

> GPU geometry budgets for the world's already-batched MultiMeshes.

`res://scripts/client/scenery_lod.gd`

## Overview

GPU geometry budgets for the world's already-batched MultiMeshes.
GeometryInstance3D LOD bias uses imported mesh LODs where available.
Visibility ranges cheaply cull far, non-critical decorations as a batch.
Game objects and their collision/loot server state are never removed.

## Constants

- `const PRESETS := [`
- `const MAX_CULL_BATCH := 4096` - Change all existing streamed visual batches in one quality update. The single-object apply() path still handles newly created chunks and props. A native profile resolves up to 4096 decorative AABBs per script-to-C++ call, instead of issuing one native call per MultiMesh during quality swaps.

## Documented variables

- `static var _cull_native: Object = null` - Unreal Cull Distance Volume-inspired pure size-pair resolution. The native engine resolves nearest longest-side size, unsorted pairs, and a designer-authored max draw distance. Stock Godot uses the same policy.
- `static var _decor_profile_sizes: PackedFloat32Array = PackedFloat32Array([1.0, 4.0, 10.0, 24.0, 64.0])` - Cached profile presets avoid allocating two arrays and revalidating the same size-distance pairs for every streamed decorative MultiMesh instance. One immutable profile is configured per quality tier. Older custom engines and stock Godot use the same cached packed arrays with the legacy method.

## Functions

### `preset`

```gdscript
static func preset(quality: int) -> Dictionary
```

### `foliage_fade_width`

```gdscript
static func foliage_fade_width(quality: int) -> float
```

Dither distance, only for high-fidelity foliage; low tiers keep zero
extra fragment work. Culling remains the existing MultiMesh end range.

### `category`

```gdscript
static func category(kind: String) -> String
```

### `range_for`

```gdscript
static func range_for(kind: String, quality: int, base_distance: float = 0.0) -> float
```

### `cull_range_for_bounds`

```gdscript
static func cull_range_for_bounds(bounds: AABB, sizes: PackedFloat32Array, ranges: PackedFloat32Array, authored_distance: float, prefer_native: bool = true) -> float
```

Public game wrapper for both Cgame and stock Godot. -1 from an invalid
native profile is not applied to the scene.

### `decor_range_for_bounds`

```gdscript
static func decor_range_for_bounds(bounds: AABB, quality: int, authored_distance: float, prefer_native: bool = true) -> float
```

Size-distance pairs are quality-scaled but never override the category or
the author's draw cap. Large batches remain unchanged (zero cull range).
Never affects gameplay objects, terrain collisions or landmarks.

### `apply`

```gdscript
static func apply(instance: MultiMeshInstance3D, kind: String, quality: int, base_distance: float = 0.0) -> void
```

### `apply_many`

```gdscript
static func apply_many(nodes: Array, quality: int) -> void
```

_4 private function(s) starting with `_` are not listed._
