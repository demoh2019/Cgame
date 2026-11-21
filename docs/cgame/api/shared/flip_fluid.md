# flip_fluid.gd

> 2D FLIP/PIC fluid on a MAC (staggered) grid with solid cells and a moving circle obstacle.

`res://scripts/shared/flip_fluid.gd`

## Overview

2D FLIP/PIC fluid on a MAC (staggered) grid with solid cells and a moving circle obstacle.

Method: Zhu & Bridson, "Animating Sand as a Fluid", SIGGRAPH 2005 (FLIP) and
Harlow & Welch 1965 (MAC grid / PIC).
The structure of the step (particle push-apart, particle-to-grid transfer with
bilinear weights, Gauss-Seidel pressure projection with over-relaxation, density
based drift compensation, PIC/FLIP blend on the way back) follows Matthias Müller's
"Ten Minute Physics" tutorial 18 "How to write a FLIP water/fluid simulation",
https://github.com/matthias-research/pages (MIT License, Copyright (c) 2022
Matthias Müller). Re-written in GDScript with y-up coordinates, interleaved
velocity storage, destructible walls (set_solid) and an obstacle that is also
a particle collider. Velocity grid: component 0 = u on left cell faces,
component 1 = v on bottom cell faces, index = (i * rows + j) * 2 + component.

## Constants

- `const FLUID := 0`
- `const AIR := 1`
- `const SOLID := 2`

## Functions

### `particle_count`

```gdscript
func particle_count() -> int
```

### `particle_positions`

```gdscript
func particle_positions() -> PackedVector2Array
```

### `cell_of`

```gdscript
func cell_of(p_pos: Vector2) -> Vector2i
```

### `cell_type_at`

```gdscript
func cell_type_at(cell: Vector2i) -> int
```

### `is_wall`

```gdscript
func is_wall(cell: Vector2i) -> bool
```

### `set_solid`

```gdscript
func set_solid(cell: Vector2i, solid: bool) -> void
```

Turns a cell into a wall or opens it again (destructible barrier). The outer border is permanent.

### `set_obstacle`

```gdscript
func set_obstacle(center: Vector2, radius: float, velocity: Vector2 = Vector2.ZERO) -> void
```

### `clear_obstacle`

```gdscript
func clear_obstacle() -> void
```

### `add_water_block`

```gdscript
func add_water_block(lo: Vector2, hi: Vector2) -> int
```

Fills a box with a hex lattice of particles (skipping walls); returns how many were added.

### `step`

```gdscript
func step(dt: float) -> void
```

### `divergence_max`

```gdscript
func divergence_max() -> float
```

Largest |divergence| over fluid cells of the current grid velocity.

### `average_height`

```gdscript
func average_height() -> float
```

### `kinetic_energy`

```gdscript
func kinetic_energy() -> float
```

_13 private function(s) starting with `_` are not listed._
