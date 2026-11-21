# zombie_flies.gd

> Flies buzzing around the nearest zombies (DayZ / Days Gone rot detail): a small pool of swirling particle swarms re-assigned to the closest infected 5x a sec...

`res://scripts/client/zombie_flies.gd`

## Overview

Flies buzzing around the nearest zombies (DayZ / Days Gone rot detail): a small
pool of swirling particle swarms re-assigned to the closest infected 5x a
second. Daytime and dry weather only; off on Performance/Balanced.

## Constants

- `const POOL := 4`
- `const RADIUS := 16.0`

## Functions

### `swarm_count`

```gdscript
static func swarm_count(level: int, daylight: float, storm: float) -> int
```

### `update_view`

```gdscript
func update_view(entities: Node, player: Vector3, daylight: float, storm: float, level: int, delta: float) -> void
```

_1 private function(s) starting with `_` are not listed._
