# bike_integrity.gd

> Server-owned bicycle frame integrity.

`res://scripts/shared/bike_integrity.gd`

## Overview

Server-owned bicycle frame integrity. Independent of chain servicing and tire grips.
The inventory bike remains a tradeable item; no client controls repair or damage.

## Constants

- `const BIKE_ID := "salvage_bike"`
- `const KIT_ID := "bike_frame_patch"`
- `const MAX_INTEGRITY := 100.0`
- `const REPAIR_POINTS := 45.0`
- `const HIT_DAMAGE := 20.0`
- `const WEAR_PER_METER := 0.025`

## Functions

### `valid`

```gdscript
static func valid(value: Variant) -> bool
```

### `can_ride`

```gdscript
static func can_ride(value: float) -> bool
```

### `speed_factor`

```gdscript
static func speed_factor(value: float) -> float
```

### `terrain_wear`

```gdscript
static func terrain_wear(biome: String) -> float
```

### `after_ride`

```gdscript
static func after_ride(current: float, biome: String, actual_meters: float) -> float
```

### `after_hit`

```gdscript
static func after_hit(current: float) -> float
```

### `repair_reason`

```gdscript
static func repair_reason(inventory, current: float) -> String
```

### `after_repair`

```gdscript
static func after_repair(current: float) -> float
```

