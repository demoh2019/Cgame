# evasion.gd

> Shared collision-aware dodge geometry.

`res://scripts/shared/evasion.gd`

## Overview

Shared collision-aware dodge geometry. All rule enforcement is on GameServer.
Keep the displacement in short steps so a dodge cannot jump through thin walls.

## Constants

- `const Movement = preload("res://scripts/shared/movement.gd")`
- `const STAMINA_COST := 24.0`
- `const COOLDOWN := 3.0`
- `const INVULNERABLE_TO_INFECTED := 0.30`
- `const ATTACK_LOCK := 0.32`
- `const SPEED := 8.0`
- `const STEP := 0.08`
- `const STEPS := 4`
- `const MIN_DISPLACEMENT := 0.08`

## Functions

### `destination`

```gdscript
static func destination(world, origin: Vector3, input_direction: Vector2) -> Vector3
```

### `moved_distance`

```gdscript
static func moved_distance(origin: Vector3, destination_position: Vector3) -> float
```

