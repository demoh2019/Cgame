# breath_vapor.gd

> Visible breath in cold air (Red Dead Redemption 2 signature detail): a soft puff leaves the mouth on each exhale, more often while running.

`res://scripts/client/breath_vapor.gd`

## Overview

Visible breath in cold air (Red Dead Redemption 2 signature detail): a soft
puff leaves the mouth on each exhale, more often while running. Cold comes
from altitude (snow line), snowfall and clear mountain/snow nights.
CPU particles, a handful at a time; off on Performance.

## Constants

- `const MOUTH_HEIGHT := 1.6`

## Functions

### `coldness`

```gdscript
static func coldness(ground_height: float, daylight: float, biome: String, snowing: float) -> float
```

0..1 cold from ground height (m), daylight, biome and snowfall.

### `exhale_interval`

```gdscript
static func exhale_interval(speed: float) -> float
```

Seconds between exhales: ~3.5 s at rest, ~1.2 s while sprinting.

### `update_view`

```gdscript
func update_view(cold: float, speed: float, level: int, delta: float) -> void
```

_1 private function(s) starting with `_` are not listed._
