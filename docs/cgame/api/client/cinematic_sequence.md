# cinematic_sequence.gd

> Sequencer-style cinematic timeline data model: multi-shot camera cuts, transform / float / event / animation tracks, sampling and serialization.

`res://scripts/client/cinematic_sequence.gd`

## Overview

```text
Sequencer-style cinematic timeline data model: multi-shot camera cuts,
transform / float / event / animation tracks, sampling and serialization.

References (concepts only, implementation written from scratch):
- Catmull-Rom splines: Edwin Catmull & Raphael Rom (public domain math);
  positions use Godot's Vector3.cubic_interpolate.
- Squad (spherical cubic quaternion interpolation): Shoemake 1985,
  formulation as in the public-domain math notes by Ken Shoemake / Eberly.
- Track/key/shot model inspired by Unreal Sequencer and Unity Timeline
  (design ideas only, no code copied).
```

## Functions

### `add_shot`

```gdscript
func add_shot(start: float, end: float, camera: String) -> void
```

### `add_transform_key`

```gdscript
func add_transform_key(track: String, key: Dictionary) -> void
```

### `add_float_key`

```gdscript
func add_float_key(track: String, key: Dictionary) -> void
```

### `add_event`

```gdscript
func add_event(track: String, time: float, event_name: String, args: Array = []) -> void
```

### `add_animation_key`

```gdscript
func add_animation_key(track: String, time: float, target: String, animation: String) -> void
```

### `sample_transform`

```gdscript
func sample_transform(track: String, t: float) -> Transform3D
```

### `apply_ease`

```gdscript
static func apply_ease(w: float, ease_name: String) -> float
```

### `sample_float`

```gdscript
func sample_float(track: String, t: float) -> float
```

### `events_between`

```gdscript
func events_between(t0: float, t1: float) -> Array
```

Events with t0 <= time < t1, sorted by time. When t1 < t0 the range wraps
through the end of the sequence: [t0, length) then [0, t1).

### `animations_between`

```gdscript
func animations_between(t0: float, t1: float) -> Array
```

### `active_shot`

```gdscript
func active_shot(t: float) -> Dictionary
```

### `camera_cut_blend`

```gdscript
func camera_cut_blend(t: float, blend_seconds: float) -> Dictionary
```

{"from": String, "to": String, "weight": float}; weight 0 shows `from`,
1 shows `to`. Only the first blend_seconds of a shot blend from the
previous shot's camera.

### `to_dict`

```gdscript
func to_dict() -> Dictionary
```

### `from_dict`

```gdscript
static func from_dict(d: Dictionary) -> RefCounted
```

_9 private function(s) starting with `_` are not listed._
