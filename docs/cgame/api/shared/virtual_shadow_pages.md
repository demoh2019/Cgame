# virtual_shadow_pages.gd

> CPU-side virtual shadow map page manager: clipmap levels, fixed-size pages, page requests from visible receivers, caster invalidation and an LRU physical pag...

`res://scripts/shared/virtual_shadow_pages.gd`

## Overview

CPU-side virtual shadow map page manager: clipmap levels, fixed-size pages,
page requests from visible receivers, caster invalidation and an LRU
physical page pool with cross-frame cache reuse.

Concepts follow the publicly documented design of Virtual Shadow Maps
(Epic Games, "Virtual Shadow Maps" docs / SIGGRAPH talks) and the clipmap
idea of Tanner et al. 1998. This is an independent clean-room implementation
from those descriptions; no Unreal Engine source code was used or copied.
Original code, MIT-compatible.

## Functions

### `setup`

```gdscript
func setup(clipmap_levels: int, level0_world_size: float, page_size_texels: int, virtual_res: int, physical_pages: int) -> void
```

### `level_world_size`

```gdscript
func level_world_size(level: int) -> float
```

### `page_world_size`

```gdscript
func page_world_size(level: int) -> float
```

### `texel_world_size`

```gdscript
func texel_world_size(level: int) -> float
```

### `begin_frame`

```gdscript
func begin_frame(light_dir: Vector3, camera_pos: Vector3) -> void
```

Starts a frame: rebuilds the light basis and recentres each clipmap by whole
pages (global page coordinates keep cached pages valid across recentring).

### `clipmap_center`

```gdscript
func clipmap_center(level: int) -> Vector2i
```

### `level_for_footprint`

```gdscript
func level_for_footprint(footprint: float) -> int
```

Smallest level whose texel size covers the receiver's pixel footprint.

### `request_for_receivers`

```gdscript
func request_for_receivers(points: PackedVector3Array, pixel_footprints: PackedFloat32Array) -> void
```

### `invalidate_casters`

```gdscript
func invalidate_casters(aabbs_moved: Array) -> void
```

Marks cached pages overlapping moved caster AABBs dirty. Static casters are
simply never passed in, so their pages stay cached.

### `end_frame`

```gdscript
func end_frame() -> Dictionary
```

Resolves requests against the physical pool.
Returns {allocated, reused, rendered, evicted, dropped, requested, resident}.

### `resident_count`

```gdscript
func resident_count() -> int
```

### `is_resident`

```gdscript
func is_resident(level: int, gx: int, gy: int) -> bool
```

### `page_table`

```gdscript
func page_table() -> PackedInt32Array
```

Toroidal page table for shaders: levels * pages_per_axis^2 ints holding the
physical slot, or -1 when the page is not resident. Index:
level*N*N + (gy mod N)*N + (gx mod N).

_2 private function(s) starting with `_` are not listed._
