# rain_harvest.gd

> Weather-driven survival resource loop.

`res://scripts/shared/rain_harvest.gd`

## Overview

Weather-driven survival resource loop. All checks are deterministic and
server-authoritative. Water is paid for with a crafted tarp and, in swamps,
an actual charcoal filter; no client may claim the rain or choose yields.

## Constants

- `const Weather = preload("res://scripts/shared/weather.gd")`
- `const Inventory = preload("res://scripts/shared/inventory.gd")`
- `const TARP_ITEM := "rain_tarp"`
- `const FILTER_ITEM := "charcoal_filter"`
- `const WATER_ITEM := "water_bottle"`
- `const WATER_COUNT := 2`
- `const COOLDOWN_SECONDS := 90.0`
- `const MIN_SLOPE_NORMAL_Y := 0.72`

## Functions

### `site_reason`

```gdscript
static func site_reason(world, position: Vector3, world_seconds: float) -> String
```

### `needs_filter`

```gdscript
static func needs_filter(world, position: Vector3) -> bool
```

### `transact`

```gdscript
static func transact(inventory: Inventory, polluted: bool) -> Dictionary
```

Full atomic transaction. No payer inputs/output numbers are taken from RPC.

