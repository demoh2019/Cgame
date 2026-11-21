# mesh_fracture.gd

> Runtime mesh fracturing for destructible props: turns Voronoi cells into render meshes, convex collision shapes and physics debris, with fracture LOD.

`res://scripts/client/mesh_fracture.gd`

## Overview

Runtime mesh fracturing for destructible props: turns Voronoi cells into
render meshes, convex collision shapes and physics debris, with fracture LOD.
Original code; cell generation lives in res://scripts/shared/voronoi_fracture.gd.

## Constants

- `const VoronoiFracture = preload("res://scripts/shared/voronoi_fracture.gd")`
- `const DENSITY := 500.0`

## Functions

### `build_fragments`

```gdscript
static func build_fragments(cells: Array, material: Material = null) -> Array
```

Per cell: {"mesh": ArrayMesh, "shape": ConvexPolygonShape3D, "center", "volume"}.
Mesh and shape are centred on `center` so a body can sit at that point.

### `spawn_debris`

```gdscript
static func spawn_debris(parent: Node3D, origin: Transform3D, fragments: Array, impulse_point: Vector3, impulse: float, lifetime: float = 8.0) -> Array
```

Spawns one RigidBody3D per fragment under `parent`. `origin` is the prop's
transform in parent space; `impulse_point` is in parent space too.

### `lod_count`

```gdscript
static func lod_count(distance: float) -> int
```

Hierarchical fracture LOD: fewer pieces the farther the camera.

