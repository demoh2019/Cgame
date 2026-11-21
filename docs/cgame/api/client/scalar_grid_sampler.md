# scalar_grid_sampler.gd

> Wrapped lattice-grid sampler for PCG texture fields, clouds and weather.

`res://scripts/client/scalar_grid_sampler.gd`

## Overview

Wrapped lattice-grid sampler for PCG texture fields, clouds and weather.
Native Cgame interpolates all UV queries in one call. Standard Godot
uses the same two-axis periodic interpolation in GDScript.

## Functions

### `sample_wrapped`

```gdscript
static func sample_wrapped(grid: PackedFloat32Array, size: Vector2i, uvs: PackedVector2Array, smooth: bool = true, force_scalar: bool = false) -> PackedFloat32Array
```

