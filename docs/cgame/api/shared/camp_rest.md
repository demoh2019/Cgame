# camp_rest.gd

> Settlement recovery: repair the survivor, not a field teleport heal.

`res://scripts/shared/camp_rest.gd`

## Overview

Settlement recovery: repair the survivor, not a field teleport heal.
Existing inventory and survival APIs provide atomic ingredient use.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const COOLDOWN := 90.0`
- `const COST := {"wood_1": 2, "canned_food": 1, "water_bottle": 1}`
- `const HEALTH_RECOVERY := 25.0`
- `const STAMINA_RECOVERY := 55.0`
- `const HUNGER_RECOVERY := 15.0`
- `const THIRST_RECOVERY := 15.0`

## Functions

### `needs_recovery`

```gdscript
static func needs_recovery(vitals) -> bool
```

### `has_supplies`

```gdscript
static func has_supplies(inventory) -> bool
```

### `recover`

```gdscript
static func recover(inventory, vitals) -> bool
```

Called only after the server has checked hub position, action state,
life, cooldown and meaningful missing vitals. No partial ingredient debit.

