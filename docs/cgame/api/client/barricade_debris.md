# barricade_debris.gd

> Destroyed barricades burst into physical Voronoi debris (Chaos Geometry Collection style).

`res://scripts/client/barricade_debris.gd`

## Overview

Destroyed barricades burst into physical Voronoi debris (Chaos Geometry
Collection style). Fracture patterns are baked once per LOD piece count
and reused, so a siege does not re-run hull clipping per wall.

## Constants

- `const VoronoiFracture = preload("res://scripts/shared/voronoi_fracture.gd")`
- `const MeshFracture = preload("res://scripts/client/mesh_fracture.gd")`
- `const PANEL := Vector3(1.6, 1.2, 0.3)`
- `const MAX_PIECES := 12 # Cosmetic only: never more bodies than this per wall.`
- `const LIFETIME := 6.0`

## Functions

### `pieces_for`

```gdscript
static func pieces_for(distance: float) -> int
```

### `fragments`

```gdscript
static func fragments(count: int) -> Array
```

### `spawn`

```gdscript
static func spawn(parent: Node3D, at: Vector3, viewer: Vector3, yaw: float = 0.0) -> Array
```

Spawns debris at a broken wall; returns the bodies (empty when far away).

