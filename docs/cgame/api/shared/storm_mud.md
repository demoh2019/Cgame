# storm_mud.gd

> Seeded storms soften exposed ground.

`res://scripts/shared/storm_mud.gd`

## Overview

Seeded storms soften exposed ground. Roads retain traction even in rain.
No state is persisted: both server and client derive the same effect from
world seed, position and authoritative world time.

## Constants

- `const Weather = preload("res://scripts/shared/weather.gd")`
- `const RoadTravel = preload("res://scripts/shared/road_travel.gd")`
- `const ROAD_PROTECTION := 0.85`
- `const FOOT_LOSS := {`
- `const BIKE_LOSS := {`

## Functions

### `traction`

```gdscript
static func traction(weather: Dictionary, biome: String, road_coverage: float, mounted: bool) -> float
```

Pure factor. The benefit of a road cannot exceed 85% of the rain loss;
pre-existing road travel bonuses still apply independently.

### `factor`

```gdscript
static func factor(world, position: Vector3, seconds: float, mounted: bool) -> float
```

Only the server supplies time for authoritative input processing. The
prediction code uses the most recent replicated server clock instead of
receiving an untrusted network-supplied traction multiplier.

