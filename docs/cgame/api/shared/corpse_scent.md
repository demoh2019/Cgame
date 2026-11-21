# corpse_scent.gd

> Blood-marked death loot is a temporary location cue for idle infected.

`res://scripts/shared/corpse_scent.gd`

## Overview

Blood-marked death loot is a temporary location cue for idle infected.
Only server-confirmed kills may attach a scent to a real loot bag.

## Constants

- `const DURATION := 40.0`
- `const RADIUS := 22.0`

## Functions

### `mark`

```gdscript
static func mark(bag: Dictionary, now: float) -> bool
```

### `active`

```gdscript
static func active(bag: Dictionary, now: float) -> bool
```

### `buckets`

```gdscript
static func buckets(bags: Dictionary, now: float) -> Dictionary
```

Fixed-cell index: nearby infected search at most nine buckets.

### `closest`

```gdscript
static func closest(index: Dictionary, enemy_position: Vector3, now: float) -> Dictionary
```

Closest corpse only, ties settled by server-generated bag ID.

