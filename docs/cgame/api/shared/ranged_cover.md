# ranged_cover.gd

> Deterministic 2D ray/solid intersection for authoritative ranged combat.

`res://scripts/shared/ranged_cover.gd`

## Overview

Deterministic 2D ray/solid intersection for authoritative ranged combat.
Uses the world's movement blocker broadphase, including constructed walls.

## Functions

### `first_blocker`

```gdscript
static func first_blocker(world, origin: Vector2, direction: Vector2, reach: float, min_radius: float = 0.0) -> Dictionary
```

The server needs both first-hit distance and collider identity. Static
scenery may have an id too; the game server separately checks barricades.
Empty means the ray is clear. Invalid rays fail closed at distance zero.

### `first_blocker_distance`

```gdscript
static func first_blocker_distance(world, origin: Vector2, direction: Vector2, reach: float, min_radius: float = 0.0) -> float
```

Original cover API stays available for every existing caller.

