# wading_wetness.gd

> Shallow-water crossings soak survivors through their real world position.

`res://scripts/shared/wading_wetness.gd`

## Overview

Shallow-water crossings soak survivors through their real world position.
Rain, wind chill, cold and the existing character save already use wetness.
The server never accepts a client-supplied water depth or wetness amount.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const WetClothing = preload("res://scripts/shared/wet_clothing.gd")`
- `const MAX_DEPTH := 1.0 # Movement blocks deeper water.`
- `const BASE_SOAK_PER_SECOND := 1.0`
- `const DEPTH_SOAK_PER_SECOND := 4.0`

## Functions

### `depth_at`

```gdscript
static func depth_at(world, position: Vector3) -> float
```

Ankle-to-waist water, derived from world terrain (not input).
Deep water is not walkable and cannot be used for a wetness exploit.

### `after_weather`

```gdscript
static func after_weather(previous: float, weather_next: float, delta: float, depth: float) -> float
```

When physically standing in water, neither a roof nor a warm campfire can
dry clothing. Rain ingress still stacks with immersion. No water means the
existing weather/campfire drying rules are preserved exactly.

