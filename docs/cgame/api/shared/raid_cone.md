# raid_cone.gd

> Server-only raid warlord directional cleave, locked when telegraphed.

`res://scripts/shared/raid_cone.gd`

## Overview

Server-only raid warlord directional cleave, locked when telegraphed.
No client controls aim, hit positions, angle, damage or attack timings.

## Constants

- `const REACH := 13.0`
- `const HEIGHT_LIMIT := 3.5`
- `const HALF_ANGLE_DEGREES := 38.0`
- `const MIN_AIM_DISTANCE := 0.4`
- `const WINDUP_SECONDS := 2.2`
- `const FIRST_COOLDOWN := 22.0`
- `const ENRAGED_COOLDOWN := 15.0`
- `const FIRST_DAMAGE := 24.0`
- `const ENRAGED_DAMAGE := 33.0`

## Functions

### `can_aim`

```gdscript
static func can_aim(origin: Vector3, target: Vector3) -> bool
```

### `direction`

```gdscript
static func direction(origin: Vector3, target: Vector3) -> Vector2
```

### `in_sector`

```gdscript
static func in_sector(origin: Vector3, aim: Vector2, victim: Vector3) -> bool
```

### `cooldown`

```gdscript
static func cooldown(boss) -> float
```

### `damage`

```gdscript
static func damage(boss) -> float
```

