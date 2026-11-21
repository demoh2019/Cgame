# movement.gd

> One step of player movement.

`res://scripts/shared/movement.gd`

## Overview

One step of player movement. The server runs it to decide where a player is, and the client runs
the very same function to predict its own player, so the two agree except when something the
client could not know (another player is not an obstacle here) intervenes.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const StealthStance = preload("res://scripts/shared/stealth_stance.gd")`
- `const Mounts = preload("res://scripts/shared/mounts.gd")`
- `const BikeTerrain = preload("res://scripts/shared/bike_terrain.gd")`
- `const BikeIntegrity = preload("res://scripts/shared/bike_integrity.gd")`
- `const RoadTravel = preload("res://scripts/shared/road_travel.gd")`
- `const StormMud = preload("res://scripts/shared/storm_mud.gd")`
- `const WadingTravel = preload("res://scripts/shared/wading_travel.gd")`
- `const Swimming = preload("res://scripts/shared/swimming.gd")`
- `const MAX_DELTA := 0.1 # A longer step is clamped, so a lag spike cannot teleport a player.`

## Functions

### `step`

```gdscript
static func step(world, position: Vector3, input: Dictionary, delta: float) -> Vector3
```

`input` has "x", "z" (a move direction, any length up to 1) and "sprint". Returns the new position
(y follows the ground). Water that is too deep and solid objects stop the player, and sliding
along them keeps the movement smooth.

### `move`

```gdscript
static func move(world, position: Vector3, direction: Vector2, speed: float, delta: float, allow_swim: bool = false) -> Vector3
```

Moves along `direction` (unit or shorter) at `speed` meters per second. Shared by players and zombies.

### `sweep_displacement`

```gdscript
static func sweep_displacement(world, position: Vector3, displacement: Vector2, max_meters: float = 3.0) -> Vector3
```

Short, server-authored physical impulses use many collision-checked
substeps. A single large move() call could leap across a narrow blocker.
Reuse the same water, solid-obstacle and wall-slide rules as locomotion.
This primitive does not apply any damage or authorize PvP displacement.

_2 private function(s) starting with `_` are not listed._
