# hearty_meal.gd

> Classless cooked-meal bonus.

`res://scripts/shared/hearty_meal.gd`

## Overview

Classless cooked-meal bonus. Server owns the food, duration, tick and save.
Food only enhances recovery while hydrated and nourished; it never heals
wounds or raises stamina/combat energy over their existing caps.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const MAX_DURATION := 210.0`

## Functions

### `tier_for_food`

```gdscript
static func tier_for_food(item_id: String) -> int
```

### `duration`

```gdscript
static func duration(tier: int) -> float
```

### `stamina_per_second`

```gdscript
static func stamina_per_second(tier: int) -> float
```

### `energy_per_second`

```gdscript
static func energy_per_second(tier: int) -> float
```

### `valid_state`

```gdscript
static func valid_state(seconds: Variant, tier: Variant) -> bool
```

The rank and time must be consistent, with strict types and finite numbers.
Zero-time, zero-rank is the only inactive state. Legacy saves default to it.

### `bonus_seconds`

```gdscript
static func bonus_seconds(seconds: float, delta: float) -> float
```

Integrate only seconds that the buff is actually active (even with big ticks).
Recovery is blocked by starvation/dehydration and stamina recovery delay.

### `stamina_seconds`

```gdscript
static func stamina_seconds(active_seconds: float, recovery_delay: float) -> float
```

