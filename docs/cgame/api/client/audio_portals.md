# audio_portals.gd

> Portal-based sound propagation between rooms (Wwise Rooms & Portals concept): Dijkstra over portals, geometric path length, virtual source position, closed-p...

`res://scripts/client/audio_portals.gd`

## Overview

Portal-based sound propagation between rooms (Wwise Rooms & Portals concept):
Dijkstra over portals, geometric path length, virtual source position,
closed-portal attenuation and a UTD-inspired diffraction low-pass cutoff.
Concepts from Wwise/Steam Audio docs and the Uniform Theory of Diffraction
(Kouyoumjian & Pathak); implemented from scratch.

## Constants

- `const CLOSED_PORTAL_DB := 40.0`
- `const MAX_CUTOFF_HZ := 20000.0`
- `const MIN_CUTOFF_HZ := 200.0`

## Functions

### `add_room`

```gdscript
func add_room(id: Variant, center: Vector3) -> void
```

### `add_portal`

```gdscript
func add_portal(room_a: Variant, room_b: Variant, position: Vector3, openness: float = 1.0) -> int
```

Returns the portal id (usable in propagate()'s "path").

### `set_openness`

```gdscript
func set_openness(portal_id: int, openness: float) -> void
```

### `propagate`

```gdscript
func propagate(source_room: Variant, source_pos: Vector3, listener_room: Variant, listener_pos: Vector3) -> Dictionary
```

### `cutoff_for_bend`

```gdscript
static func cutoff_for_bend(bend_radians: float) -> float
```

UTD-inspired: shadow-region loss grows with bend angle, so the cutoff falls
roughly with 1 / (1 + k * theta^2).

_4 private function(s) starting with `_` are not listed._
