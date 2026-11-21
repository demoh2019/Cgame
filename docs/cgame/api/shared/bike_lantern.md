# bike_lantern.gd

> A crafted bicycle lantern makes night travel easier but exposes its rider.

`res://scripts/shared/bike_lantern.gd`

## Overview

A crafted bicycle lantern makes night travel easier but exposes its rider.
The server owns toggle state and throttling; client packets contain only item use.

## Constants

- `const ITEM_ID := "bike_dynamo_lamp"`
- `const BIKE_ID := "salvage_bike"`
- `const REVEAL_RADIUS := 23.0`
- `const TOGGLE_COOLDOWN := 0.8`

## Functions

### `toggle_reason`

```gdscript
static func toggle_reason(inventory, now: float, last_toggle: float) -> String
```

### `lit`

```gdscript
static func lit(inventory, mounted: bool, alive: bool, night: bool, enabled: bool = true) -> bool
```

### `reveal_radius`

```gdscript
static func reveal_radius(inventory, mounted: bool, alive: bool, night: bool, enabled: bool = true) -> float
```

