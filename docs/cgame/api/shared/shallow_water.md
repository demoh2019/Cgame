# shallow_water.gd

> Shallow-water heightfield solver using the virtual pipes method (Mei, Decaudin, Hu 2007, "Fast Hydraulic Erosion Simulation and Visualization on GPU").

`res://scripts/shared/shallow_water.gd`

## Overview

Shallow-water heightfield solver using the virtual pipes method (Mei, Decaudin,
Hu 2007, "Fast Hydraulic Erosion Simulation and Visualization on GPU").
Each cell exchanges water with its 4 neighbours through pipes driven by the
surface height difference. Outflow is scaled so a cell never gives away more
than it holds (depth stays >= 0) and boundaries are closed, so volume is
conserved. Intended for floods and puddles, in the spirit of Unreal's
Water/Fluid Flux and flood systems in survival games.

## Constants

- `const GRAVITY: float = 9.81`
- `const FLUX_DAMPING: float = 0.999`
- `const MAX_SUBSTEPS: int = 32`

## Functions

### `setup`

```gdscript
func setup(grid_w: int, grid_h: int, cell: float, terrain: PackedFloat32Array) -> void
```

### `add_water`

```gdscript
func add_water(cell: Vector2i, depth: float) -> void
```

### `depth_at`

```gdscript
func depth_at(cell: Vector2i) -> float
```

### `terrain_at`

```gdscript
func terrain_at(cell: Vector2i) -> float
```

### `total_volume`

```gdscript
func total_volume() -> float
```

### `velocity_at`

```gdscript
func velocity_at(cell: Vector2i) -> Vector2
```

### `step`

```gdscript
func step(delta: float) -> void
```

_2 private function(s) starting with `_` are not listed._
