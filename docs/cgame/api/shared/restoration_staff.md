# restoration_staff.gd

> Server-side bounds for an equipment-granted, group-only healing pulse.

`res://scripts/shared/restoration_staff.gd`

## Overview

Server-side bounds for an equipment-granted, group-only healing pulse.
No client-provided target, effect strength or range is ever accepted.

## Constants

- `const RANGE := 8.0`
- `const MAX_HEIGHT := 2.5`
- `const MAX_TARGETS := 2`
- `const BASE_HEAL := 8.0`
- `const PER_TIER_HEAL := 4.0`

## Functions

### `heal_for_tier`

```gdscript
static func heal_for_tier(tier: int) -> float
```

### `can_reach`

```gdscript
static func can_reach(source: Vector3, target: Vector3) -> bool
```

### `urgency`

```gdscript
static func urgency(health: float, maximum: float) -> float
```

Health deficit determines target priority; invalid and healthy actors are ignored.

