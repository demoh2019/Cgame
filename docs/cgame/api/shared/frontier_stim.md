# frontier_stim.gd

> Rare, crafted combat stimulant: immediate recovery paid for with thirst.

`res://scripts/shared/frontier_stim.gd`

## Overview

Rare, crafted combat stimulant: immediate recovery paid for with thirst.
Activation and cooldown are server owned; relog or death never resets it.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const ITEM_ID := "frontier_stim"`
- `const COOLDOWN := 90.0`
- `const STAMINA_RESTORE := 50.0`
- `const ENERGY_RESTORE := 35.0`
- `const THIRST_COST := 12.0`
- `const MIN_TOTAL_DEFICIT := 20.0`

## Functions

### `ready`

```gdscript
static func ready(survival, energy: float, cooldown: float) -> String
```

### `apply`

```gdscript
static func apply(survival, energy: float) -> float
```

Call only after a server inventory debit succeeds and ready() returned "".
No health, damage, infection, or armor bonuses: existing PvP stays fair.

