# swimming.gd

> Swimming and diving for survivors on foot.

`res://scripts/shared/swimming.gd`

## Overview

Swimming and diving for survivors on foot. Shared by the authoritative server
and client prediction (Movement.step), so both agree where a swimmer is.
Deep water used to be a wall; now survivors swim at the surface and dive while
crouching. Diving uses breath; at zero breath the survivor drowns. Infected
and bicycles still cannot enter deep water.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const SWIM_DEPTH := 1.0 # Deeper than this, feet leave the bottom.`
- `const SURFACE_BODY := 1.25 # Body (feet) sits this far below the surface: head stays above water.`
- `const DIVE_DEPTH := 3.6 # A diver's body sinks this far below the surface (or to the bottom).`
- `const SWIM_SPEED_FACTOR := 0.62`
- `const DIVE_SPEED_FACTOR := 0.55`
- `const MAX_BREATH := 100.0`
- `const BREATH_DRAIN := 8.5 # Per second underwater: about 12 s of air.`
- `const BREATH_REFILL := 35.0 # Per second with the head above water.`
- `const DROWN_DAMAGE := 12.0 # Health per second once breath runs out.`
- `const EEL_MIN_ZONE := 1`
- `const EEL_CHANCE_PER_SECOND := 0.07`
- `const EEL_DAMAGE_PER_ZONE := 7.0`

## Functions

### `depth_at`

```gdscript
static func depth_at(world, x: float, z: float) -> float
```

### `is_swimming`

```gdscript
static func is_swimming(world, x: float, z: float) -> bool
```

### `body_y`

```gdscript
static func body_y(world, x: float, z: float, diving: bool) -> float
```

Height of the swimmer's feet: near the surface, or deeper while diving, never below the bottom.

### `submerged`

```gdscript
static func submerged(world, x: float, z: float, diving: bool) -> bool
```

Whether the swimmer's head is under the surface.

### `speed_factor`

```gdscript
static func speed_factor(diving: bool) -> float
```

### `breathe`

```gdscript
static func breathe(breath: float, underwater: bool, delta: float) -> Vector2
```

Next breath value and the drowning damage taken over `delta`.

### `eel_chance`

```gdscript
static func eel_chance(zone: int, safe: bool, delta: float) -> float
```

Eel bite chance this tick for a diver in a dangerous zone (0 when safe).

### `eel_damage`

```gdscript
static func eel_damage(zone: int) -> float
```

