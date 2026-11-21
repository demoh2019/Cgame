# siege_waves.gd

> Predictable, bounded server-driven infected attacks on defended survivors.

`res://scripts/shared/siege_waves.gd`

## Overview

Predictable, bounded server-driven infected attacks on defended survivors.
No player RPC can create a wave or select a spawn position. Waves are an
event during the live session; persistent building data is unchanged.

## Constants

- `const WorldCycle = preload("res://scripts/shared/world_cycle.gd")`
- `const Structures = preload("res://scripts/shared/structures.gd")`
- `const Movement = preload("res://scripts/shared/movement.gd")`
- `const CHECK_EVERY_TICKS := 20`
- `const GLOBAL_COOLDOWN := 45.0`
- `const WALL_COOLDOWN := 180.0`
- `const MAX_ACTIVE_ZOMBIES := 90`
- `const MAX_PER_WAVE := 5`
- `const PLAYER_WALL_RANGE := 26.0`
- `const MIN_PLAYER_SPAWN_DISTANCE := 10.0`
- `const MAX_PLAYER_SPAWN_DISTANCE := 28.0 # Every spawned enemy can acquire its target.`
- `const SPAWN_RADII := [15.0, 20.0, 24.0]`
- `const SPAWN_ANGLES := 12`

## Functions

### `wave_size`

```gdscript
static func wave_size(tier: int) -> int
```

### `eligible`

```gdscript
static func eligible(wall: Dictionary, player_position: Vector3, world_time: float) -> bool
```

### `spawn_sites`

```gdscript
static func spawn_sites(world, wall: Dictionary, survivor: Vector3, count: int, offset: int = 0) -> Array[Vector2]
```

Defensive spawn search. Never materialize infected inside a survivor,
structure, natural collider, protected hub or deep water.

