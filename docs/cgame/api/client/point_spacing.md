# point_spacing.gd

> Ordered geometry self-pruning: use Cgame's bounded spatial hash when available, otherwise retain exact scalar semantics in stock Godot.

`res://scripts/client/point_spacing.gd`

## Overview

Ordered geometry self-pruning: use Cgame's bounded spatial hash when
available, otherwise retain exact scalar semantics in stock Godot.

## Functions

### `keep_indices`

```gdscript
static func keep_indices(points: PackedVector2Array, separation: float, max_keep: int = -1, force_scalar: bool = false) -> PackedInt32Array
```

### `candidates`

```gdscript
static func candidates(rng: RandomNumberGenerator, rect: Rect2, attempts: int, separation: float, max_keep: int, force_scalar: bool = false) -> PackedVector2Array
```

Bounded decorative scatter selection: generate more candidates than needed
and prune once before any mesh creation or height/biome sampling.

