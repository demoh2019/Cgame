# mining_wedges.gd

> High-tier mining preparation trades extra yield for louder infected hearing.

`res://scripts/shared/mining_wedges.gd`

## Overview

High-tier mining preparation trades extra yield for louder infected hearing.
A single paid kit grants three server-verified, capacity-aware harvests.

## Constants

- `const ITEM_ID := "mining_wedges"`
- `const CHARGES := 3`
- `const EXTRA_YIELD := 2`
- `const MIN_TIER := 2`
- `const NOISE_RADIUS := 42.0`

## Functions

### `valid_state`

```gdscript
static func valid_state(value: Variant) -> bool
```

Saved integer charges are a bounded legacy-compatible account field.

### `use_reason`

```gdscript
static func use_reason(inventory, charges: int) -> String
```

### `bonus`

```gdscript
static func bonus(kind: String, tier: int, charges: int, free_space: int, ordinary_amount: int, authenticated: bool) -> int
```

Only real T2+ rock/ore gathers can spend a charge. The entire ordinary
harvest plus bonus must fit, otherwise keep the charge and ordinary yield.
No PvP, wood, berry, quest or fishing reward can trigger this bonus.

### `harvest_noise`

```gdscript
static func harvest_noise(base: float, bonus_added: int) -> float
```

