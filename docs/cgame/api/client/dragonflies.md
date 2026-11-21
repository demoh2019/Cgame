# dragonflies.gd

> Dragonflies skimming over water on warm days (Ghost of Tsushima / RDR2 nature ambience) on the engine's native Flock3D: fast, low-cohesion darting just above...

`res://scripts/client/dragonflies.gd`

## Overview

Dragonflies skimming over water on warm days (Ghost of Tsushima / RDR2 nature
ambience) on the engine's native Flock3D: fast, low-cohesion darting just
above the surface near the player. Empty on engines without Flock3D.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const FishShoals = preload("res://scripts/client/fish_shoals.gd")`
- `const MAX_FLIES := 8`

## Functions

### `count`

```gdscript
static func count(level: int, daylight: float, storm: float) -> int
```

### `update_view`

```gdscript
func update_view(world, player: Vector3, daylight: float, storm: float, level: int, delta: float, underground: bool) -> void
```

_2 private function(s) starting with `_` are not listed._
