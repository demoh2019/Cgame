# buoyancy.gd

> Rigid-body buoyancy.

`res://scripts/client/buoyancy.gd`

## Overview

Rigid-body buoyancy. Every RigidBody3D in the "buoyant" group that dips below the water surface
(sea, river or lake: WorldGen.water_level_at) is pushed up in proportion to how deep it sits,
damped in the water, and drifts with river current and the wind - so debris, severed limbs and
dropped wreckage float, bob and drift instead of sinking through the surface.

## Constants

- `const VegetationWind = preload("res://scripts/client/vegetation_wind.gd")`
- `const GROUP := "buoyant"`
- `const DENSITY_LIFT := 1.7 # Upward force at full submersion, in units of the body's weight.`
- `const DEPTH_FOR_FULL := 0.35`
- `const WATER_DAMP := 2.4`

_1 private function(s) starting with `_` are not listed._
