# xpbd_cloth.gd

> XPBD cloth: distance (stretch + shear) and bending constraints with compliance, sub-stepping, sphere/capsule/plane collision, spatial-hash self-collision and...

`res://scripts/shared/xpbd_cloth.gd`

## Overview

XPBD cloth: distance (stretch + shear) and bending constraints with compliance, sub-stepping,
sphere/capsule/plane collision, spatial-hash self-collision and tearing.

Algorithm: Macklin, Muller, Chentanez "XPBD: Position-Based Simulation of Compliant
Constrained Dynamics" (2016); structure follows Matthias Muller's "Ten Minute Physics"
cloth demo (small-steps XPBD, 1 solver iteration per substep, hash-grid self collision).
Source: https://github.com/matthias-research/pages (tenMinutePhysics), MIT License,
(c) Matthias Muller / NVIDIA. This is a clean GDScript re-implementation from the
published algorithm, not a verbatim copy; no GPL/LGPL code was used.

Grid layout: particle (i, j) sits at origin * (i*spacing, -j*spacing, 0), so row 0 is the
top edge, local -Y is "down the cloth" and local +Z is the front-face normal.

## Constants

- `const KIND_STRETCH := 0`
- `const KIND_SHEAR := 1`
- `const KIND_BEND := 2`

## Documented variables

- `var wind := Vector3.ZERO` - Wind velocity the air tries to drag particles toward; with wind == 0 this is plain drag.
- `var drag := 0.1` - Air drag rate in 1/s toward the wind velocity.
- `var compliance_stretch := 0.0` - Compliance (inverse stiffness, m/N) per constraint family; 0 = fully rigid.
- `var iterations := 1` - Solver iterations per substep (Ten Minute Physics uses 1 with many substeps).
- `var collision_margin := 0.01` - Particle radius used for collider contact.
- `var friction := 0.2` - Tangential damping on contact, 0..1.
- `var tear_threshold := 0.0` - Stretch constraints longer than rest * tear_threshold are removed (0 disables tearing).
- `var thickness := 0.04` - Minimum distance kept between non-neighbouring particles when self_collision_enabled.

## Functions

### `setup_grid`

```gdscript
func setup_grid(width_cells: int, height_cells: int, spacing: float, origin: Transform3D, particle_mass: float = 1.0) -> void
```

### `particle_count`

```gdscript
func particle_count() -> int
```

### `constraint_count`

```gdscript
func constraint_count() -> int
```

### `stretch_constraint_count`

```gdscript
func stretch_constraint_count() -> int
```

### `columns`

```gdscript
func columns() -> int
```

### `rows`

```gdscript
func rows() -> int
```

### `index_of`

```gdscript
func index_of(i: int, j: int) -> int
```

### `max_stretch_error`

```gdscript
func max_stretch_error() -> float
```

Largest |length / rest - 1| over stretch constraints (0 when none remain).

### `pin`

```gdscript
func pin(index: int, world_pos: Vector3) -> void
```

Fix particle `index` at a world position (inverse mass becomes 0).

### `attach`

```gdscript
func attach(index: int, target_fn: Callable) -> void
```

Make particle `index` follow `target_fn.call() -> Vector3` (e.g. an animated bone socket).

### `unpin`

```gdscript
func unpin(index: int) -> void
```

### `is_pinned`

```gdscript
func is_pinned(index: int) -> bool
```

### `add_sphere`

```gdscript
func add_sphere(center: Vector3, radius: float) -> int
```

### `set_sphere_center`

```gdscript
func set_sphere_center(index: int, center: Vector3) -> void
```

### `add_capsule`

```gdscript
func add_capsule(a: Vector3, b: Vector3, radius: float) -> int
```

### `set_capsule`

```gdscript
func set_capsule(index: int, a: Vector3, b: Vector3) -> void
```

### `add_plane`

```gdscript
func add_plane(normal: Vector3, offset: float) -> int
```

Half-space n . x >= offset is free; particles are pushed out of the other side.

### `clear_colliders`

```gdscript
func clear_colliders() -> void
```

### `set_particle`

```gdscript
func set_particle(index: int, world_pos: Vector3) -> void
```

Teleport a free particle (position and history), e.g. to pre-fold the cloth.

### `positions`

```gdscript
func positions() -> PackedVector3Array
```

### `velocities`

```gdscript
func velocities() -> PackedVector3Array
```

### `triangles`

```gdscript
func triangles() -> PackedInt32Array
```

### `step`

```gdscript
func step(dt: float, substeps: int = 8) -> void
```

### `normals`

```gdscript
func normals() -> PackedVector3Array
```

### `build_mesh`

```gdscript
func build_mesh() -> ArrayMesh
```

_10 private function(s) starting with `_` are not listed._
