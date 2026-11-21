# tumbleweeds.gd

> Wind-blown tumbleweeds on open plains (RDR2 / western ambience): a few brush balls roll downwind, hop over bumps and respawn upwind out of view.

`res://scripts/client/tumbleweeds.gd`

## Overview

Wind-blown tumbleweeds on open plains (RDR2 / western ambience): a few brush
balls roll downwind, hop over bumps and respawn upwind out of view. Purely
visual and client-side; off on Performance, in calm air and off the plains.

## Constants

- `const WEED_SHADER := preload("res://assets/shaders/tumbleweed.gdshader")`
- `const MAX_WEEDS := 3`
- `const SPAWN_DISTANCE := 32.0`
- `const DESPAWN_DISTANCE := 45.0`
- `const MIN_WIND := 0.25`

## Functions

### `weed_count`

```gdscript
static func weed_count(level: int, biome: String, wind: Vector2) -> int
```

### `spawn_point`

```gdscript
static func spawn_point(player: Vector3, wind: Vector2, lateral: float) -> Vector3
```

Upwind spawn point around the player (weeds then roll past them).

### `update_view`

```gdscript
func update_view(world, player: Vector3, biome: String, wind: Vector2, level: int, delta: float, underground: bool) -> void
```

_1 private function(s) starting with `_` are not listed._
