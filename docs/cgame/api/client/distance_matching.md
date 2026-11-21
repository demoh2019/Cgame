# distance_matching.gd

> Distance Matching and Orientation Warping, inspired by UE5 Lyra locomotion (Distance Matching for starts/stops/pivots, Orientation Warping for strafing).

`res://scripts/client/distance_matching.gd`

## Overview

Distance Matching and Orientation Warping, inspired by UE5 Lyra locomotion
(Distance Matching for starts/stops/pivots, Orientation Warping for strafing).

## Functions

### `playback_time_for_distance`

```gdscript
static func playback_time_for_distance(distance_curve: PackedFloat32Array, times: PackedFloat32Array, remaining_distance: float) -> float
```

Inverse of a monotonic distance curve: returns the playback time at which the
animation has `remaining_distance` left. Works for increasing or decreasing curves.

### `stride_play_rate`

```gdscript
static func stride_play_rate(actual_speed: float, authored_speed: float, min_rate: float = 0.75, max_rate: float = 1.35) -> float
```

Stride warping: playback rate that makes the authored stride match actual speed.

### `orientation_warp`

```gdscript
static func orientation_warp(velocity_dir: Vector2, facing_yaw: float, max_angle: float = deg_to_rad(60.0)) -> Dictionary
```

Orientation warping. velocity_dir is the horizontal travel direction, yaw
convention atan2(x, y). Returns the lower-body offset (clamped) and the opposite
upper-body counter-rotation so the torso keeps facing the aim direction.
Backwards travel is folded so back-pedalling needs no warp.

