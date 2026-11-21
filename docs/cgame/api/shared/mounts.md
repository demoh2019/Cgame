# mounts.gd

> Bike travel permissions.

`res://scripts/shared/mounts.gd`

## Overview

Bike travel permissions. Only the server decides mount speed and eligibility.

## Constants

- `const BikeCargo = preload("res://scripts/shared/bike_cargo.gd")`
- `const BikeIntegrity = preload("res://scripts/shared/bike_integrity.gd")`
- `const ITEM_ID := "salvage_bike"`
- `const SPEED_FACTOR := 1.9`
- `const MANUAL_COOLDOWN := 2.0`
- `const HIT_COOLDOWN := 12.0`
- `const NOISE_RADIUS := 27.0`
- `const NOISE_SECONDS := 0.9`
- `const MIN_NOISY_MOVEMENT := 0.01`

## Functions

### `noise_for_distance`

```gdscript
static func noise_for_distance(meters: float) -> float
```

### `refusal`

```gdscript
static func refusal(player, now: float) -> String
```

