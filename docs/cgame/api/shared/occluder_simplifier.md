# occluder_simplifier.gd

> Builds cheap occluder geometry for OcclusionRaster and ranks candidates by screen-space value.

`res://scripts/shared/occluder_simplifier.gd`

## Overview

Builds cheap occluder geometry for OcclusionRaster and ranks candidates by screen-space value.
Original code; concepts from Intel MOC (Apache-2.0) and Frostbite/Killzone-style occluder selection.

## Functions

### `box_occluder`

```gdscript
static func box_occluder(aabb: AABB) -> PackedVector3Array
```

12 triangles (36 vertices) of an axis-aligned box.

### `from_mesh`

```gdscript
static func from_mesh(mesh: Mesh, max_tris: int) -> PackedVector3Array
```

Keeps the max_tris largest triangles of the mesh (large flat faces make the best occluders).

### `select_occluders`

```gdscript
static func select_occluders(candidates: Array, camera_pos: Vector3, budget: int) -> Array
```

Ranks candidates (AABB, or Dictionary with an "aabb" key) by approximate projected area
(largest face area / distance^2) and returns up to `budget` of them, best first.

### `score`

```gdscript
static func score(box: AABB, camera_pos: Vector3) -> float
```

