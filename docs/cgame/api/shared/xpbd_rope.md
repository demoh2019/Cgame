# xpbd_rope.gd

> XPBD rope: a particle chain with distance (and optional bending) constraints, sphere/plane collision, segment-segment self-collision through a spatial hash a...

`res://scripts/shared/xpbd_rope.gd`

## Overview

XPBD rope: a particle chain with distance (and optional bending) constraints, sphere/plane
collision, segment-segment self-collision through a spatial hash and a crossing-number
knot heuristic.

Algorithm: Macklin, Muller, Chentanez "XPBD: Position-Based Simulation of Compliant
Constrained Dynamics" (2016); small-steps solver layout after Matthias Muller's
"Ten Minute Physics" demos. Source: https://github.com/matthias-research/pages
(tenMinutePhysics), MIT License, (c) Matthias Muller / NVIDIA. Clean GDScript
re-implementation from the published algorithm; closest-point-between-segments is the
textbook (Ericson, Real-Time Collision Detection) formulation. No GPL/LGPL code was used.

## Documented variables

- `var compliance := 0.0` - Compliance of the segment distance constraints; 0 = inextensible.
- `var bend_compliance := -1.0` - Compliance of the skip-one bending constraint; negative disables bending resistance.
- `var radius := 0.02` - Rope radius, used for collider contact and self-collision (contact at 2 * radius).

## Functions

### `setup`

```gdscript
func setup(start: Vector3, end: Vector3, segments: int, particle_mass: float = 0.1) -> void
```

Straight rope from start to end with `segments` segments (segments + 1 particles).

### `setup_points`

```gdscript
func setup_points(points: PackedVector3Array, particle_mass: float = 0.1) -> void
```

Rope through an explicit polyline; rest lengths are the polyline's segment lengths.

### `particle_count`

```gdscript
func particle_count() -> int
```

### `segment_count`

```gdscript
func segment_count() -> int
```

### `positions`

```gdscript
func positions() -> PackedVector3Array
```

### `length`

```gdscript
func length() -> float
```

Current arc length of the rope.

### `rest_length`

```gdscript
func rest_length() -> float
```

### `pin`

```gdscript
func pin(index: int, world_pos: Vector3) -> void
```

### `attach`

```gdscript
func attach(index: int, target_fn: Callable) -> void
```

### `attach_start`

```gdscript
func attach_start(target_fn: Callable) -> void
```

### `attach_end`

```gdscript
func attach_end(target_fn: Callable) -> void
```

### `unpin`

```gdscript
func unpin(index: int) -> void
```

### `add_sphere`

```gdscript
func add_sphere(center: Vector3, sphere_radius: float) -> int
```

### `set_sphere_center`

```gdscript
func set_sphere_center(index: int, center: Vector3) -> void
```

### `add_plane`

```gdscript
func add_plane(normal: Vector3, offset: float) -> int
```

Half-space n . x >= offset is free.

### `clear_colliders`

```gdscript
func clear_colliders() -> void
```

### `step`

```gdscript
func step(dt: float, substeps: int = 8) -> void
```

### `closest_params`

```gdscript
static func closest_params(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Vector2
```

Closest points between segments p1-q1 and p2-q2; returns Vector2(s, t) parameters.

### `segment_distance`

```gdscript
func segment_distance(i: int, j: int) -> float
```

Smallest distance between two rope segments (indices into the segment list).

### `min_self_distance`

```gdscript
func min_self_distance() -> float
```

Smallest distance between any two non-adjacent segments.

### `crossing_number`

```gdscript
func crossing_number() -> int
```

Number of self-crossings of the polyline projected along its thinnest axis.

### `knot_count`

```gdscript
func knot_count() -> int
```

Heuristic: the simplest non-trivial knot (trefoil) needs 3 projected crossings, so every
three crossings count as one knot; a single loop or a clasp of two crossings is not a knot.

_9 private function(s) starting with `_` are not listed._
