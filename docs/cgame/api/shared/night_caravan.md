# night_caravan.gd

> A real, night-time delivery premium for trade routes.

`res://scripts/shared/night_caravan.gd`

## Overview

A real, night-time delivery premium for trade routes. Only confirmed server
movement with all cargo advances the journal; no client supplied waypoints,
distance, time, zone, route IDs, silver amounts or progress are accepted.

Progress never goes backwards. Only NEW forward progress counts toward the
night quota, so walking circles, reversing and waiting cannot farm credit.

## Constants

- `const NIGHT_BONUS_RATE := 0.20`
- `const MAX_BONUS_SILVER := 28`
- `const MIN_NIGHT_METERS := 80.0`
- `const MAX_REQUIRED_METERS := 160.0`
- `const MAX_STEP_METERS := 4.0`
- `const MIN_DANGER_ZONE := 1`

## Functions

### `initial`

```gdscript
static func initial(route: Dictionary) -> Dictionary
```

### `valid_state`

```gdscript
static func valid_state(value: Variant, route: Dictionary) -> bool
```

### `record`

```gdscript
static func record(state: Dictionary, route: Dictionary, before: Vector3, after: Vector3, night: bool, zone: int, cargo_count: int, safe: bool = false) -> bool
```

All positions are the result of the server's Movement.step, after collision.
Progress on a route is counted once at its farthest forward projection.
'night' and 'zone' are read from the server world, never from network data.

### `required_meters`

```gdscript
static func required_meters(route: Dictionary) -> float
```

### `earned_bonus`

```gdscript
static func earned_bonus(route: Dictionary, state: Dictionary) -> int
```

### `public_state`

```gdscript
static func public_state(route: Dictionary, state: Dictionary) -> Dictionary
```

_1 private function(s) starting with `_` are not listed._
