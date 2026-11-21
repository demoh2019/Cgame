# wading_travel.gd

> Shallow-water drag on foot and bicycles, driven by real terrain depth.

`res://scripts/shared/wading_travel.gd`

## Overview

Shallow-water drag on foot and bicycles, driven by real terrain depth.
Both the authoritative server and predictive client use this rule.

## Constants

- `const WadingWetness = preload("res://scripts/shared/wading_wetness.gd")`
- `const SPRINT_MAX_DEPTH := 0.25 # More than ankle-deep: no sprinting.`
- `const FOOT_DRAG_AT_ONE_METER := 0.35`
- `const BIKE_DRAG_AT_ONE_METER := 0.45`

## Functions

### `can_sprint`

```gdscript
static func can_sprint(world, position: Vector3) -> bool
```

The server checks before charging sprint stamina; shared Movement.step
also checks so a forged sprint flag cannot grant speed in the water.

### `factor`

```gdscript
static func factor(world, position: Vector3, mounted: bool) -> float
```

Existing foot and bike speed factors continue to stack multiplicatively.
Depth is capped by the same 1 m limit enforced by world collision.

