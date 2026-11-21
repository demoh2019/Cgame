# blood_scent.gd

> Blood scent gives infected a short, bounded way to find bleeding survivors.

`res://scripts/shared/blood_scent.gd`

## Overview

Blood scent gives infected a short, bounded way to find bleeding survivors.
Only the authoritative server supplies the actual wound severity to AI.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const MIN_BLEEDING := 12.0`
- `const BASE_RANGE := 18.0`
- `const RANGE_PER_BLEEDING := 0.12`
- `const MAX_RANGE := 30.0`

## Functions

### `detection_radius`

```gdscript
static func detection_radius(bleeding: float, alive: bool = true, safe: bool = false, masked: bool = false) -> float
```

Returns zero for treated, dead, protected or invalid survivors.
The zombie brain further caps detection to the enemy's pursuit leash.

