# bike_cargo.gd

> Crafted saddlebags shift part of carried weight onto an owned bicycle.

`res://scripts/shared/bike_cargo.gd`

## Overview

Crafted saddlebags shift part of carried weight onto an owned bicycle.
They do NOT create inventory slots, reduce loot/drop weight or improve on-foot speed.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const TrailBackpack = preload("res://scripts/shared/trail_backpack.gd")`
- `const ITEM_ID := "bike_panniers"`
- `const BIKE_ID := "salvage_bike"`
- `const SUPPORTED_KG := 28.0`

## Functions

### `installed`

```gdscript
static func installed(inventory) -> bool
```

### `effective_weight`

```gdscript
static func effective_weight(inventory, riding: bool) -> float
```

### `movement_factor`

```gdscript
static func movement_factor(inventory, skill_bonus: float, riding: bool) -> float
```

