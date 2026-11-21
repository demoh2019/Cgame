# rested_training.gd

> Paid hub and field recovery grants a bounded extra-XP reserve.

`res://scripts/shared/rested_training.gd`

## Overview

Paid hub and field recovery grants a bounded extra-XP reserve.
Only GameServer._award converts this reserve into character experience.

## Constants

- `const MAX_CREDIT := 120`
- `const HUB_GRANT := 30`
- `const FIELD_GRANT := 15`
- `const BONUS_RATE := 0.25`

## Functions

### `valid_credit`

```gdscript
static func valid_credit(value: Variant) -> bool
```

### `refill`

```gdscript
static func refill(current: int, field: bool) -> int
```

### `bonus_for`

```gdscript
static func bonus_for(amount: float, credit: int) -> int
```

Credit is measured in *additional*, not base, skill XP. Partial XP,
malformed amounts and already exhausted reserves never create a bonus.

