# terrain_curvature.gd

> Seam-continuous cavity/ridge vertex color baking.

`res://scripts/client/terrain_curvature.gd`

## Overview

Seam-continuous cavity/ridge vertex color baking. The engine receives a
one-sample height halo, ensuring neighbors across streamed chunks match.
The CPU bake runs once per chunk; stock Godot retains scalar parity.

## Constants

- `const CAVITY_START := 0.015`
- `const CAVITY_END := 0.32`
- `const RIDGE_START := 0.015`
- `const RIDGE_END := 0.42`

## Functions

### `build`

```gdscript
static func build(heights: PackedFloat32Array, origin: Vector2, side: int, spacing: float, world_height: Callable, force_scalar: bool = false) -> PackedColorArray
```

R = concave cavity, G = convex ridge, B = baked open sky, A = opaque.
A shared height sampler is called only for the four edge strips.

