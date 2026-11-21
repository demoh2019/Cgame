# spore_sampling.gd

> Risky world-bound gathering.

`res://scripts/shared/spore_sampling.gd`

## Overview

Risky world-bound gathering. Failed inventory transfers cannot consume a kit,
and only the server can decide the actual swamp, source and exposure.

## Constants

- `const Inventory = preload("res://scripts/shared/inventory.gd")`
- `const KIT_ID := "spore_sampler"`
- `const CULTURE_ID := "spore_culture"`
- `const CULTURES_PER_KIT := 2`
- `const COOLDOWN_SECONDS := 150.0`
- `const BASE_INFECTION := 5.0`

## Functions

### `site_reason`

```gdscript
static func site_reason(world, position: Vector3) -> String
```

### `infection_cost`

```gdscript
static func infection_cost(protection: float) -> float
```

### `transact`

```gdscript
static func transact(inventory: Inventory) -> Dictionary
```

