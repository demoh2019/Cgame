# sph_fluid.gd

> 3D position-based fluids (PBF) particle solver.

`res://scripts/shared/sph_fluid.gd`

## Overview

3D position-based fluids (PBF) particle solver.

Algorithm: Macklin & Müller, "Position Based Fluids", ACM TOG 32(4), 2013
(density constraint solved with Jacobi iterations, artificial pressure term
against tensile instability, XSPH viscosity, vorticity confinement), built on
the SPH kernels of Müller, Charypar & Gross, "Particle-Based Fluid Simulation
for Interactive Applications", SCA 2003 (poly6 for density, spiky for gradients).
Written from the published equations; no third-party source code copied.
Reference implementations consulted for structure: Matthias Müller's
Ten Minute Physics demos (MIT licence, https://github.com/matthias-research/pages).

Fixed-box domain with a uniform counting-sort grid for neighbour search,
sphere obstacles with two-way momentum transfer, optional vorticity confinement.

## Constants

- `const BASE_DENSITY := 1000.0`
- `const MAX_SPEED := 20.0`

## Documented variables

- `var attraction := 0.0` - 0 = density constraint only repels (surface particles are never pulled in); 1 = full PBF.

## Functions

### `add_particle`

```gdscript
func add_particle(p_pos: Vector3, p_vel: Vector3 = Vector3.ZERO) -> void
```

### `add_block`

```gdscript
func add_block(lo: Vector3, hi: Vector3) -> int
```

Fills the axis-aligned box [lo, hi] with a cubic lattice; returns the number added.

### `particle_count`

```gdscript
func particle_count() -> int
```

### `positions`

```gdscript
func positions() -> PackedVector3Array
```

### `velocities`

```gdscript
func velocities() -> PackedVector3Array
```

### `average_density`

```gdscript
func average_density() -> float
```

### `add_sphere_obstacle`

```gdscript
func add_sphere_obstacle(center: Vector3, radius: float, velocity: Vector3 = Vector3.ZERO, p_mass: float = 0.0) -> int
```

Adds a sphere obstacle. mass <= 0 makes it kinematic (velocity never changes);
otherwise fluid impulses change its velocity (two-way coupling). Returns its index.

### `obstacle_position`

```gdscript
func obstacle_position(index: int) -> Vector3
```

### `obstacle_velocity`

```gdscript
func obstacle_velocity(index: int) -> Vector3
```

### `kinetic_energy`

```gdscript
func kinetic_energy() -> float
```

### `total_momentum`

```gdscript
func total_momentum() -> Vector3
```

### `step`

```gdscript
func step(dt: float, iterations: int = 4) -> void
```

_9 private function(s) starting with `_` are not listed._
