# bike_terrain.gd

> Terrain-aware bicycle handling.

`res://scripts/shared/bike_terrain.gd`

## Overview

Terrain-aware bicycle handling. Used by the SAME movement code on the
authoritative server and predictive clients. No client-supplied grip values.

## Constants

- `const RoadTravel = preload("res://scripts/shared/road_travel.gd")`
- `const BikeGrip = preload("res://scripts/shared/bike_grip.gd")`
- `const SAMPLE_DISTANCE := 2.0`
- `const MIN_TRACTION := 0.40`
- `const MAX_TRACTION := 1.08`
- `const UPHILL_COST := 1.25`
- `const DOWNHILL_GAIN := 0.25`

## Functions

### `surface_factor`

```gdscript
static func surface_factor(biome: String) -> float
```

### `speed_factor`

```gdscript
static func speed_factor(world, position: Vector3, direction: Vector2, grip_seconds: float = 0.0) -> float
```

Direction is normalized to avoid forged input lengths altering grade sampling.
The sample is from the deterministic, terrain-levelled world on both peers.

