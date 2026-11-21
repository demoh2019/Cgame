# field_water.gd

> Fictional lake-water risk and one-use field filtration.

`res://scripts/shared/field_water.gd`

## Overview

Fictional lake-water risk and one-use field filtration.
The dedicated server checks shore access and owns the contamination outcome.
No client input controls contamination, reward or the cooldown.

## Constants

- `const FILTER_ITEM := "charcoal_filter"`
- `const COOLDOWN_SECONDS := 12.0`
- `const THIRST_RESTORED := 35.0`
- `const UNTREATED_INFECTION := 8.0`
- `const SHORE_REACH := 3.0`
- `const SHORE_SAMPLES := 8`

## Functions

### `can_access_lake`

```gdscript
static func can_access_lake(world, position: Vector3) -> bool
```

### `needs_drink`

```gdscript
static func needs_drink(vitals) -> bool
```

