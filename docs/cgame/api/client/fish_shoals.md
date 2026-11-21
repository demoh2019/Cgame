# fish_shoals.gd

> Fish shoals in lakes and rivers (RDR2-style living water) on the engine's native Flock3D boids: one shoal near the player, below the surface, only where the ...

`res://scripts/client/fish_shoals.gd`

## Overview

Fish shoals in lakes and rivers (RDR2-style living water) on the engine's
native Flock3D boids: one shoal near the player, below the surface, only where
the water around it is deep enough. One MultiMesh draw call, no script per fish.
Needs the engine fork's Flock3D; otherwise this node stays empty.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const FISH_SHADER := preload("res://assets/shaders/fish_swim.gdshader")`
- `const MIN_DEPTH := 1.3`
- `const SHOAL_RADIUS := 5.0`
- `const SEARCH_INTERVAL := 1.0`
- `const MAX_FISH := 14`

## Functions

### `shoal_size`

```gdscript
static func shoal_size(level: int) -> int
```

Fish per shoal for a quality tier (Performance: none).

### `deep_enough`

```gdscript
static func deep_enough(world, x: float, z: float) -> bool
```

True when a whole shoal circle around (x, z) is deep enough water.

### `update_view`

```gdscript
func update_view(world, player: Vector3, level: int, daylight: float, delta: float, underground: bool) -> void
```

_3 private function(s) starting with `_` are not listed._
