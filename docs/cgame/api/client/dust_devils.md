# dust_devils.gd

> Dust devils on dry windy plains (RDR2 ambience): now and then a spinning column of dust wanders past the player with the wind for ~25 s.

`res://scripts/client/dust_devils.gd`

## Overview

Dust devils on dry windy plains (RDR2 ambience): now and then a spinning
column of dust wanders past the player with the wind for ~25 s. One CPU
particle swirl, reused; off on Performance, in calm/wet weather and off-plains.

## Constants

- `const LIFE := 25.0`

## Functions

### `allowed`

```gdscript
static func allowed(level: int, biome: String, wind: Vector2, storm: float, daylight: float) -> bool
```

### `strength`

```gdscript
static func strength(age: float) -> float
```

Fade-in/out of the column over its life (0..1).

### `update_view`

```gdscript
func update_view(world, player: Vector3, biome: String, wind: Vector2, storm: float, daylight: float, level: int, delta: float) -> void
```

_1 private function(s) starting with `_` are not listed._
