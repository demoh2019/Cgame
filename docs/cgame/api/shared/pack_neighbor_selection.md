# pack_neighbor_selection.gd

> Stock/older-engine fallback for the native nearest-neighbor broadphase.

`res://scripts/shared/pack_neighbor_selection.gd`

## Overview

Stock/older-engine fallback for the native nearest-neighbor broadphase.
Indices are sorted by distance then original index to select a bounded
cohort; output is again sorted by index to keep server alert order stable.

## Functions

### `choose`

```gdscript
static func choose(positions: PackedVector2Array, source_index: int, candidates: Array[int], radius: float, max_neighbors: int) -> PackedInt32Array
```

