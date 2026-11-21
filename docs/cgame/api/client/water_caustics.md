# water_caustics.gd

> Sun-filtered shallow-water caustic strength shared by all game terrain.

`res://scripts/client/water_caustics.gd`

## Overview

Sun-filtered shallow-water caustic strength shared by all game terrain.
Profile selection is GPU global; weather updates only one scalar at 5 Hz.
No CPU texture generation, scene nodes or per-chunk material duplication.

## Constants

- `const UPDATES_PER_SECOND := 5.0`

## Functions

### `light_factor`

```gdscript
static func light_factor(daylight: float, sun_height: float, storm: float) -> float
```

### `quality_strength`

```gdscript
static func quality_strength(level: int, rendering_method: String) -> float
```

Only Forward+ High/Ultra spends GPU cycles on fine water patterns.
A disabled shader global lets low-end renderers avoid the near-field math.

