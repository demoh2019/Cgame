# terrain_seam_normals.gd

> Generate seamless heightfield normals from the same deterministic world height function used by the terrain mesh.

`res://scripts/client/terrain_seam_normals.gd`

## Overview

Generate seamless heightfield normals from the same deterministic world
height function used by the terrain mesh. Only outside-edge samples invoke
World.height_at, so this does not multiply world-generation work per vertex.
Terrain source height min/range are applied before differentiation to match
the normalized values submitted to the engine.

## Functions

### `build`

```gdscript
static func build(raw: PackedFloat32Array, origin: Vector2, count: int, step: float, minimum: float, height_range: float, sample_world: Callable) -> PackedVector3Array
```

_1 private function(s) starting with `_` are not listed._
