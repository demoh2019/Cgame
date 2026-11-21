# motion_matching.gd

> Motion Matching pose-search database (data only, headless-testable).

`res://scripts/client/motion_matching.gd`

## Overview

```text
Motion Matching pose-search database (data only, headless-testable).

Concepts after Simon Clavet, "Motion Matching and The Road to Next-Gen
Animation" (GDC 2016, For Honor), Daniel Holden's "Learned Motion Matching"
(SIGGRAPH 2020) and his critically damped spring write-up (theorangeduck.com,
"Spring-It-On"). Implementation is original; the spring closed form is the
standard critically damped solution. Acceleration structure is a k-means
bucket index with triangle-inequality pruning, so indexed search is exact.

Feature layout (DIMS = 24):
  0..1   root velocity (local space, x right / y forward)
  2      root facing
  3..11  3 trajectory samples at 0.2/0.4/0.6 s: pos.x, pos.y, facing (relative to root)
  12..14 left foot pos, 15..17 right foot pos
  18..20 left foot vel, 21..23 right foot vel
```

## Constants

- `const DIMS: int = 24`
- `const TRAJ_TIMES: Array[float] = [0.2, 0.4, 0.6]`
- `const MIN_STD: float = 0.0001`

## Documented variables

- `var weights: Dictionary = {` - Per-feature-group weights (applied after mean/std normalisation).
- `var continue_bias: float = 0.85` - Cost multiplier for the pose that continues the currently playing clip.
- `var frame_src := PackedInt32Array()` - original frame number inside the clip

## Functions

### `add_clip`

```gdscript
func add_clip(clip_name: String, frames: Array, fps: float, loop: bool, tags := PackedStringArray()) -> void
```

### `frame_count`

```gdscript
func frame_count() -> int
```

### `stats`

```gdscript
func stats() -> Dictionary
```

### `frame_features`

```gdscript
static func frame_features(frame: Dictionary) -> PackedFloat32Array
```

### `build`

```gdscript
func build() -> void
```

### `retain_frames`

```gdscript
func retain_frames(keep: PackedByteArray) -> int
```

Drops frames where keep[i] == 0 (keeps normalisation), then rebuilds the index.

### `search`

```gdscript
func search(query: Dictionary, current_clip := "", current_frame := -1, required_tags := PackedStringArray()) -> Dictionary
```

### `brute_force_search`

```gdscript
func brute_force_search(query: Dictionary, current_clip := "", current_frame := -1, required_tags := PackedStringArray()) -> Dictionary
```

### `predict_velocity`

```gdscript
static func predict_velocity(v0: Vector2, goal: Vector2, halflife: float, t: float) -> Vector2
```

Critically damped spring on a 2D value (zero initial rate of change).

### `predict_facing`

```gdscript
static func predict_facing(facing: float, goal: float, halflife: float, t: float) -> float
```

### `query_from`

```gdscript
func query_from(velocity: Vector2, facing: float, desired_velocity: Vector2, desired_facing: float, left_foot: Vector3, right_foot: Vector3, left_vel: Vector3, right_vel: Vector3) -> Dictionary
```

_11 private function(s) starting with `_` are not listed._
