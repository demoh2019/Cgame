# terrain_horizon_ao.gd

> Native terrain-horizon AO for high-quality open-world landscape.

`res://scripts/client/terrain_horizon_ao.gd`

## Overview

Native terrain-horizon AO for high-quality open-world landscape.
A small outer height halo makes the same border vertex see exactly the
same surrounding relief when neighbouring chunks stream independently.

## Constants

- `const RADIUS_STEPS := 6`

## Functions

### `build`

```gdscript
static func build(raw: PackedFloat32Array, origin: Vector2, side: int, spacing: float, world_height: Callable, height_min: float, height_max: float) -> PackedFloat32Array
```

