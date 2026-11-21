# snow_vfx.gd

> Altitude snowfall (RDR2 mountain passes): above the terrain snow line the same weather falls as slow, swirling flakes instead of rain.

`res://scripts/client/snow_vfx.gd`

## Overview

Altitude snowfall (RDR2 mountain passes): above the terrain snow line the same
weather falls as slow, swirling flakes instead of rain. One camera-following
GPU emitter; amount_ratio follows weather so it never restarts mid-storm.

## Constants

- `const SNOW_LINE_START := 82.0 # metres; matches the terrain snow cap blend (88..108).`
- `const SNOW_LINE_FULL := 96.0`
- `const AMOUNTS := [0, 400, 900, 1500] # per quality tier; Performance off`

## Functions

### `snow_fraction`

```gdscript
static func snow_fraction(ground_height: float) -> float
```

0 = rain, 1 = snow, from the ground height under the player.

### `update_view`

```gdscript
func update_view(center: Vector3, intensity: float, level: int) -> void
```

_2 private function(s) starting with `_` are not listed._
