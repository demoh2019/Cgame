# storm_tarp_anchors.gd

> Owner-paid single-use upgrade to an already placed expedition tarp.

`res://scripts/shared/storm_tarp_anchors.gd`

## Overview

Owner-paid single-use upgrade to an already placed expedition tarp.
No extra safe zone, permanent object or additional tent slot.

## Constants

- `const PortableShelter = preload("res://scripts/shared/portable_shelter.gd")`
- `const Structures = preload("res://scripts/shared/structures.gd")`
- `const ITEM_ID := "storm_tarp_anchors"`
- `const BONUS_SECONDS := 180.0`

## Functions

### `nearest`

```gdscript
static func nearest(shelters: Dictionary, player, now: float) -> Dictionary
```

Only the server determines the nearest live structure, never an RPC ID.

### `new_expiry`

```gdscript
static func new_expiry(tarp: Dictionary, now: float) -> float
```

### `anchored_covers`

```gdscript
static func anchored_covers(shelters: Dictionary, position: Vector3, now: float) -> bool
```

Everyone inside a genuine live upgraded shelter benefits from cover.

