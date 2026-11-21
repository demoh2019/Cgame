# tree_ambush.gd

> Tree ambushers: some infected wait crouched up in a tree and drop onto whoever walks under, landing right in front of them with a hit.

`res://scripts/shared/tree_ambush.gd`

## Overview

Tree ambushers: some infected wait crouched up in a tree and drop onto whoever walks under,
landing right in front of them with a hit. Damage or a close noise wakes them early.

## Constants

- `const PERCH_HEIGHT := 3.4`
- `const TREE_SEARCH := 10.0 # A spawn can climb a tree this close.`
- `const TRIGGER_RANGE := 8.5 # Horizontal distance at which a percher leaps.`
- `const LAND_HIT_RANGE := 2.0`
- `const LAND_OFFSET := 1.1 # Lands this far in front of the target.`

## Functions

### `chance`

```gdscript
static func chance(zone: int) -> float
```

Deterministic per spawn: never in the green zone, more often deeper out.

### `rolls`

```gdscript
static func rolls(spawn_id: int, zone: int, world_seed: int) -> bool
```

### `tree_near`

```gdscript
static func tree_near(nodes: Array, x: float, z: float) -> Dictionary
```

The nearest tree node of the chunk within reach of the spawn, or {}.

### `damage`

```gdscript
static func damage(zone: int) -> float
```

