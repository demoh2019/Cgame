# spore_hazard.gd

> Deterministic airborne infection in dangerous swamps.

`res://scripts/shared/spore_hazard.gd`

## Overview

Deterministic airborne infection in dangerous swamps.
The server supplies world position, time and physically equipped armor.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const WorldCycle = preload("res://scripts/shared/world_cycle.gd")`
- `const DAY_INFECTION_PER_SECOND := 0.14`
- `const NIGHT_INFECTION_PER_SECOND := 0.28`
- `const FILTER_ITEM_ID := "spore_filter"`
- `const FILTER_DURATION_SECONDS := 120.0`
- `const FILTER_REDUCTION := 0.75`
- `const MAX_PROTECTION := 0.95`

## Functions

### `protection`

```gdscript
static func protection(armor_id: String) -> float
```

### `status`

```gdscript
static func status(world, position: Vector3, world_seconds: float, equipped_armor: String = "", filter_seconds: float = 0.0) -> Dictionary
```

A pure, snapshot-safe hazard state (no client input or writable state).

