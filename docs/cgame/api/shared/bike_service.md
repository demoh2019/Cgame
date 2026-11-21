# bike_service.gd

> Paid maintenance of a bicycle drive chain, measured from actual server travel.

`res://scripts/shared/bike_service.gd`

## Overview

Paid maintenance of a bicycle drive chain, measured from actual server travel.
This is a survivor-owned service buff, not arbitrary item metadata. No client RPC
can supply remaining metres, repair quantity, wear or sound radius.

## Constants

- `const ITEM_ID := "bike_service_kit"`
- `const BIKE_ID := "salvage_bike"`
- `const MAX_METERS := 800.0`
- `const SERVICED_NOISE_RADIUS := 17.0`

## Functions

### `valid_remaining`

```gdscript
static func valid_remaining(value: Variant) -> bool
```

### `repair_reason`

```gdscript
static func repair_reason(inventory, remaining: float) -> String
```

### `wear_for_distance`

```gdscript
static func wear_for_distance(biome: String, actual_meters: float) -> float
```

### `remaining_after_move`

```gdscript
static func remaining_after_move(remaining: float, biome: String, moved: float) -> float
```

### `riding_noise_radius`

```gdscript
static func riding_noise_radius(remaining: float, wrapped_radius: float) -> float
```

