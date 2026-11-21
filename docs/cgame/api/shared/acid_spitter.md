# acid_spitter.gd

> A special infected arcing attack.

`res://scripts/shared/acid_spitter.gd`

## Overview

A special infected arcing attack. Server chooses the landing point and
impact moment; the client merely renders the warning ground circle.

## Constants

- `const MIN_ZONE := 2 # Red and black PvP/resource tiers only.`
- `const RANGE := 12.0`
- `const MIN_RANGE := 3.0`
- `const RADIUS := 2.4`
- `const WINDUP_SECONDS := 1.4`
- `const COOLDOWN := 6.0`
- `const INFECTION_PER_HIT := 10.0`
- `const POOL_SECONDS := 5.0`
- `const POOL_DAMAGE := 3.0`
- `const POOL_INFECTION := 1.0`
- `const POOL_TICK_SECONDS := 1.0`
- `const MAX_ACTIVE_POOLS := 64`
- `const STRUCTURE_CORROSION_DAMAGE := 8.0`

## Functions

### `corrodes_wall`

```gdscript
static func corrodes_wall(center: Vector2, wall_position: Vector2, wall_radius: float) -> bool
```

### `make_pool`

```gdscript
static func make_pool(id: int, center: Vector2, ground_y: float, now: float, source_id: int) -> Dictionary
```

### `pool_remaining`

```gdscript
static func pool_remaining(pool: Dictionary, now: float) -> float
```

### `spawn_chance`

```gdscript
static func spawn_chance(zone: int) -> float
```

### `can_launch`

```gdscript
static func can_launch(distance: float) -> bool
```

### `hits`

```gdscript
static func hits(center: Vector2, target: Vector3) -> bool
```

