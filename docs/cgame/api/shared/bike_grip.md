# bike_grip.gd

> Consumable off-road bicycle tread kit.

`res://scripts/shared/bike_grip.gd`

## Overview

Consumable off-road bicycle tread kit. Both server and client use the same
deterministic surface modifier, without changing slopes, obstacles or sprint.

## Constants

- `const ITEM_ID := "trail_tire_grips"`
- `const BIKE_ID := "salvage_bike"`
- `const DURATION_SECONDS := 240.0`
- `const RECOVERY_SHARE := 0.50`

## Functions

### `apply_reason`

```gdscript
static func apply_reason(inventory, seconds: float) -> String
```

### `active`

```gdscript
static func active(seconds: float) -> bool
```

### `surface_factor`

```gdscript
static func surface_factor(biome: String, base: float, seconds: float) -> float
```

Restore half of the loss from a rough surface, but never add free speed
on firm ground, ignore slope resistance or bypass water/wall collision.

