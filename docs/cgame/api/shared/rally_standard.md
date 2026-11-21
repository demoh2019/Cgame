# rally_standard.gd

> A single temporary, material-paid squad standard.

`res://scripts/shared/rally_standard.gd`

## Overview

A single temporary, material-paid squad standard. Only the verified party
leader may deploy it; there is no client-controlled position or buff power.

## Constants

- `const ITEM_ID := "field_standard"`
- `const DURATION := 90.0`
- `const COOLDOWN := 120.0`
- `const RADIUS := 11.0`
- `const MAX_VERTICAL_DISTANCE := 3.0`
- `const STAMINA_PER_SECOND := 1.4`
- `const ENERGY_PER_SECOND := 0.8`

## Functions

### `within_range`

```gdscript
static func within_range(marker: Vector3, position: Vector3) -> bool
```

### `bonus_seconds`

```gdscript
static func bonus_seconds(now: float, delta: float, placed: float, expires: float) -> float
```

