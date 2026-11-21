# motion_db_builder.gd

> Builds / optimises Motion Matching databases without mocap.

`res://scripts/client/motion_db_builder.gd`

## Overview

Builds / optimises Motion Matching databases without mocap.
Synthetic analytic foot cycles are original work. Pruning follows the
database-optimisation idea from Clavet (GDC 2016) and UE5 Pose Search.

## Constants

- `const MotionMatching = preload("res://scripts/client/motion_matching.gd")`
- `const FPS: float = 30.0`

## Functions

### `synthesize_locomotion_clips`

```gdscript
static func synthesize_locomotion_clips() -> Array
```

Returns Array of {name, frames, fps, loop, tags}. Velocity is local (x right, y forward).

### `build_default_database`

```gdscript
static func build_default_database() -> MotionMatching
```

### `prune_redundant`

```gdscript
static func prune_redundant(db: MotionMatching, threshold: float) -> int
```

Removes frames within `threshold` (normalised, weighted distance) of an
already kept frame of the same clip. Returns the removed count.

_2 private function(s) starting with `_` are not listed._
