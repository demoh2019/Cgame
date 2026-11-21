# road_mask_max_filter.gd

> Grayscale square maximum filter / Chebyshev dilation, for procedural vegetation exclusion.

`res://scripts/client/road_mask_max_filter.gd`

## Overview

Grayscale square maximum filter / Chebyshev dilation, for procedural
vegetation exclusion. Cgame's O(N) native two-pass implementation is used
where available; stock Godot has a separable GDScript fallback.

## Functions

### `compute`

```gdscript
static func compute(mask: PackedByteArray, size: Vector2i, radius: int = 2, force_scalar: bool = false) -> PackedByteArray
```

