# sea_surface.gd

> The open sea: a radial LOD mesh that follows the camera (dense ripples close by, coarse rings out to the horizon, so Gerstner swell has vertices to move), an...

`res://scripts/client/sea_surface.gd`

## Overview

The open sea: a radial LOD mesh that follows the camera (dense ripples close by, coarse rings
out to the horizon, so Gerstner swell has vertices to move), and an island depth map so the
swell dies down and breaks into surf where the sea gets shallow. The depth map is filled
a couple of rows per frame from WorldGen.ground_at.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const SEGMENTS := 160`
- `const RADIUS := 900.0`
- `const FIRST_RING := 0.8`
- `const GROWTH := 1.065 # Each ring a little wider than the last.`
- `const MAP_SIZE := 256`
- `const MAP_EXTENT := 6400.0`
- `const ROWS_PER_FRAME := 2`

## Functions

### `build_mesh`

```gdscript
static func build_mesh() -> ArrayMesh
```

Concentric rings around the origin; ring spacing grows geometrically with distance.

### `step_depth_map`

```gdscript
func step_depth_map(world) -> bool
```

Fill a few rows of the depth map; returns true once the whole map is ready (then it is uploaded).

