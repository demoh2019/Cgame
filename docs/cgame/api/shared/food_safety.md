# food_safety.gd

> Survival choice: raw fish is edible but unsafe; cooked fish is ordinary food.

`res://scripts/shared/food_safety.gd`

## Overview

Survival choice: raw fish is edible but unsafe; cooked fish is ordinary food.
Values and tick integration are shared data, never client-provided damage.

## Constants

- `const MAX_SEVERITY := 100.0`
- `const NATURAL_RECOVERY_PER_SECOND := 0.125`
- `const THIRST_DRAIN_PER_SECOND := 0.075`
- `const DAMAGE_PER_SECOND := 0.30`
- `const MAX_HUNGER_TO_EAT_RAW := 85.0`
- `const REMEDY_ITEM := "herbal_gut_tonic"`

## Functions

### `raw_fish_tier`

```gdscript
static func raw_fish_tier(item_id: String) -> int
```

### `raw_hunger`

```gdscript
static func raw_hunger(tier: int) -> float
```

### `raw_poison`

```gdscript
static func raw_poison(tier: int) -> float
```

### `can_eat_raw`

```gdscript
static func can_eat_raw(hunger: float) -> bool
```

### `valid_severity`

```gdscript
static func valid_severity(value: Variant) -> bool
```

### `progress`

```gdscript
static func progress(severity: float, delta: float) -> Dictionary
```

Exact area integration: one 120-second tick matches 120 one-second ticks
without applying poison damage after the symptom has dissipated.

