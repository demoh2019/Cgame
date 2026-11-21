# prospecting_chart.gd

> Single-use geological survey for the tiered gathering / crafting economy.

`res://scripts/shared/prospecting_chart.gd`

## Overview

Single-use geological survey for the tiered gathering / crafting economy.
The server alone selects a real world node. Clients cannot request a
particular node ID, item quantity, reward, radius, or location.

## Constants

- `const WorldGen = preload("res://scripts/shared/world_gen.gd")`
- `const ITEM_ID := "prospecting_chart"`
- `const SCAN_RADIUS := 180.0`
- `const CHUNK_RADIUS := 3`
- `const MIN_TIER := 2`
- `const MARK_SECONDS := 80.0`

## Functions

### `nearest`

```gdscript
static func nearest(world, at: Vector3, depleted: Dictionary) -> Dictionary
```

Scan at most 49 deterministic world chunks. Highest-tier ore is preferred,
then high-tier stone, then nearest, then stable ID. All resources remain
in the world and must still be gathered with real skill and tools.

### `active`

```gdscript
static func active(mark: Dictionary, now: float, depleted: Dictionary) -> bool
```

### `public_mark`

```gdscript
static func public_mark(mark: Dictionary, now: float, depleted: Dictionary) -> Dictionary
```

Client sees only a short-lived destination, material class and tier.
Never replicate internal node IDs or absolute server deadlines.

