# wind_chill.gd

> Regional wind chill joins the seeded wind model and persistent survival.

`res://scripts/shared/wind_chill.gd`

## Overview

Regional wind chill joins the seeded wind model and persistent survival.
All inputs are obtained from the server-owned world, position and gear.

## Constants

- `const Weather = preload("res://scripts/shared/weather.gd")`
- `const PortableShelter = preload("res://scripts/shared/portable_shelter.gd")`
- `const MIN_WIND_MPS := 0.35`
- `const FULL_WIND_MPS := 1.6`
- `const COLD_RANGE_C := 18.0`
- `const MAX_EXTRA_SEVERITY := 0.22`
- `const WET_AMPLIFIER := 0.50`

## Functions

### `penalty`

```gdscript
static func penalty(conditions: Dictionary, wind: Vector2, wetness: float, armor_id: String) -> float
```

Additional 0..0.33 exposure intensity. Calm/warm or covered hub weather
gives zero; wet clothes amplify gusts, protective armor mitigates them.

### `visible`

```gdscript
static func visible(world, position: Vector3, now: float, wetness: float, armor_id: String, near_fire: bool = false, under_tarp: bool = false) -> Dictionary
```

A view of the viewer's own verified local weather. Not a state change or
remotely supplied damage. The numbers reflect tarp/fire protection to
avoid displaying a penalty that a shelter has already neutralized.

