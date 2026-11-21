# scenery_hlod_proxy.gd

> Bounded HLOD: several close-range instanced stone variants become one merged, eight-triangle-per-stone proxy surface at far camera distances.

`res://scripts/client/scenery_hlod_proxy.gd`

## Overview

Bounded HLOD: several close-range instanced stone variants become one
merged, eight-triangle-per-stone proxy surface at far camera distances.
Native Cgame builds the geometry; stock Godot uses the same fallback.
Decorative only: never modifies collisions, gathering, RNG or source meshes.

## Constants

- `const MAX_INPUT_INSTANCES := 8192`
- `const MAX_PROXY_INSTANCES := 512`
- `const MAX_COORDINATE := 10000000.0`
- `const MAX_HALF_EXTENT := 10000.0`
- `const MAX_BASIS_AXIS := 1000.0`
- `const MIN_SOURCE_INSTANCES := 8`
- `const PROXY_END_DISTANCE := 160.0`
- `const SWITCH_CEILING := 53.0`
- `const SWITCH_DEADBAND := 3.0`
- `const FACES := [`

## Functions

### `build_proxy_mesh`

```gdscript
static func build_proxy_mesh(transforms: Array[Transform3D], centers: PackedVector3Array, half_extents: PackedVector3Array, max_proxy_instances: int = MAX_PROXY_INSTANCES, prefer_native: bool = true) -> ArrayMesh
```

### `attach_proxy`

```gdscript
static func attach_proxy(parent: Node3D, transforms: Array[Transform3D], centers: PackedVector3Array, half_extents: PackedVector3Array, max_proxy_instances: int = 384, prefer_native: bool = true) -> MeshInstance3D
```

### `should_use_proxy`

```gdscript
static func should_use_proxy(distance: float, near_range: float, was_far: bool) -> bool
```

Pure hysteretic switch: one proxy draw replaces ALL near stone batches
from this chunk at long distance. Do not change render buffers or AI state.

### `switch_visible`

```gdscript
static func switch_visible(near: Array[MultiMeshInstance3D], proxy: MeshInstance3D, distance: float, near_range: float, was_far: bool) -> bool
```

_3 private function(s) starting with `_` are not listed._
