# mask_distance_field.gd

> Binary raster feature distance field, measured in eight-connected pixel steps.

`res://scripts/client/mask_distance_field.gd`

## Overview

Binary raster feature distance field, measured in eight-connected pixel steps.
Cgame uses one linear-time native call; upstream Godot uses an equivalent
bounded two-pass algorithm with the same result and no GPU dependency.

## Functions

### `compute`

```gdscript
static func compute(mask: PackedByteArray, size: Vector2i, max_distance: int = 7, force_scalar: bool = false) -> PackedByteArray
```

### `from_heights`

```gdscript
static func from_heights(heights: PackedFloat32Array, size: Vector2i, land_threshold: float, max_distance: int = 7, force_scalar: bool = false) -> PackedByteArray
```

