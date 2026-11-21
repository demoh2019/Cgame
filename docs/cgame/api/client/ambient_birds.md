# ambient_birds.gd

> Ambient bird flock (RDR2 / Far Cry style "life in the sky"): a small boids flock (cohesion, alignment, separation, home pull) circles above the player in day...

`res://scripts/client/ambient_birds.gd`

## Overview

Ambient bird flock (RDR2 / Far Cry style "life in the sky"): a small boids
flock (cohesion, alignment, separation, home pull) circles above the player
in daylight and scatters away when a storm comes. One MultiMesh draw call;
wing flaps run in the vertex shader. Client-only, no gameplay effect.

## Constants

- `const FLAP_SHADER := preload("res://assets/shaders/bird_flap.gdshader")`
- `const SeededSubstreams = preload("res://scripts/client/seeded_substreams.gd")`
- `const STREAM_POSITION := 1`
- `const STREAM_VELOCITY := 2`
- `const STREAM_WING_PHASE := 3`
- `const STREAM_NATIVE_FLOCK := 4`
- `const MAX_BIRDS := 18`
- `const ALTITUDE := 22.0`
- `const SPEED := 6.5`

## Functions

### `flock_size`

```gdscript
static func flock_size(level: int, daylight: float, storm: float) -> int
```

How many birds to show: none at night, in storms or on Performance; Balanced gets a small flock.

### `steer`

```gdscript
static func steer(i: int, pos: PackedVector3Array, vel: PackedVector3Array, count: int, home: Vector3) -> Vector3
```

One boids steering step for bird `i` (pure; tested).

### `plumage`

```gdscript
static func plumage(biome: String) -> Color
```

Gull-white over coasts and water, dark corvids inland.

### `update_view`

```gdscript
func update_view(player: Vector3, daylight: float, storm: float, level: int, delta: float, underground: bool, biome: String = "") -> void
```

### `startle`

```gdscript
func startle(point: Vector3) -> void
```

Loud event nearby (explosion, lightning, gunfire): the flock bursts apart and climbs.

_3 private function(s) starting with `_` are not listed._
