# crowd_avoidance.gd

> ORCA (Optimal Reciprocal Collision Avoidance) in 2D for large crowds.

`res://scripts/shared/crowd_avoidance.gd`

## Overview

ORCA (Optimal Reciprocal Collision Avoidance) in 2D for large crowds.

Port of the algorithm from RVO2 Library (Agent::computeNewVelocity, linearProgram1/2/3)
Source: https://github.com/snape/RVO2 -- Authors: Jur van den Berg, Stephen J. Guy,
Jamie Snape, Ming C. Lin, Dinesh Manocha -- License: Apache-2.0.
Paper: van den Berg et al., "Reciprocal n-body Collision Avoidance", ISRR 2009.
Neighbour search uses a uniform spatial hash instead of RVO2's k-d tree (O(n) average).

## Constants

- `const EPSILON := 0.00001`

## Functions

### `compute_velocities`

```gdscript
static func compute_velocities(positions: PackedVector2Array, velocities: PackedVector2Array, preferred: PackedVector2Array, radius: float, max_speed: float, time_horizon: float, neighbor_dist: float, max_neighbors: int, time_step: float = 0.1) -> PackedVector2Array
```

Returns new velocities (same order as input) that avoid collisions within time_horizon.

_4 private function(s) starting with `_` are not listed._
