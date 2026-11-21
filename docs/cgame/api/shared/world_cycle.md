# world_cycle.gd

> One simulation clock for client lighting and server-side night danger.

`res://scripts/shared/world_cycle.gd`

## Overview

One simulation clock for client lighting and server-side night danger.
The dedicated server owns time; clients use the time in authoritative snapshots.
Preserve the online world's original 900-second sunrise-to-sunrise cycle.

## Constants

- `const DAY_LENGTH := 900.0`
- `const NIGHT_NOTICE_MULTIPLIER := 1.35`

## Functions

### `phase`

```gdscript
static func phase(world_seconds: float) -> float
```

### `sun_height`

```gdscript
static func sun_height(world_seconds: float) -> float
```

### `daylight`

```gdscript
static func daylight(world_seconds: float) -> float
```

### `is_night`

```gdscript
static func is_night(world_seconds: float) -> bool
```

### `notice_multiplier`

```gdscript
static func notice_multiplier(world_seconds: float) -> float
```

