# ruin_survey.gd

> Consumable wilderness cartography.

`res://scripts/shared/ruin_survey.gd`

## Overview

Consumable wilderness cartography. The client can request a survey but
cannot supply a crate ID, location, search radius or any loot values.

## Constants

- `const WorldGen = preload("res://scripts/shared/world_gen.gd")`
- `const ITEM_ID := "ruin_survey_chart"`
- `const SCAN_RADIUS := 190.0`
- `const MARK_SECONDS := 75.0`
- `const MIN_ZONE := 2`
- `const CELL_RADIUS := 3`

## Functions

### `nearest`

```gdscript
static func nearest(world, at: Vector3, opened: Dictionary) -> Dictionary
```

Bounded 7x7 world-chunk scan, selecting the nearest live red/black ruin
crate; stable ID tiebreak makes the result deterministic across clients.

### `active`

```gdscript
static func active(mark: Dictionary, now: float, opened: Dictionary) -> bool
```

### `public_mark`

```gdscript
static func public_mark(mark: Dictionary, now: float, opened: Dictionary) -> Dictionary
```

Only the owner receives a private waypoint. Absolute server deadline and
internal crate ID are never exposed, and stale marks are suppressed.

