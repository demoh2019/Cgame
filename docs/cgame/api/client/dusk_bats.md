# dusk_bats.gd

> Dusk/night bats (RDR2 / Witcher 3 ambience) on the engine's native Flock3D: low cohesion and high separation give the jittery, darting bat flight.

`res://scripts/client/dusk_bats.gd`

## Overview

Dusk/night bats (RDR2 / Witcher 3 ambience) on the engine's native Flock3D:
low cohesion and high separation give the jittery, darting bat flight.
Fades in at dusk, stays through the night, leaves in storms and dungeons.
Needs the engine fork's Flock3D; otherwise this node stays empty.

## Constants

- `const BAT_SHADER := preload("res://assets/shaders/bat_flap.gdshader")`
- `const MAX_BATS := 12`
- `const ALTITUDE := 9.0`

## Functions

### `bat_count`

```gdscript
static func bat_count(level: int, daylight: float, storm: float) -> int
```

Bats for a quality tier and time: none in daylight, storms or on Performance.

### `update_view`

```gdscript
func update_view(player: Vector3, daylight: float, storm: float, level: int, delta: float, underground: bool) -> void
```

_2 private function(s) starting with `_` are not listed._
