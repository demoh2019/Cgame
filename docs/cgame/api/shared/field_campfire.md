# field_campfire.gd

> Short-lived warmth in the hostile world.

`res://scripts/shared/field_campfire.gd`

## Overview

Short-lived warmth in the hostile world. Camps are neither shelters for
persistence nor a substitute for permanent player-owned construction.

## Constants

- `const Structures = preload("res://scripts/shared/structures.gd")`
- `const COST := {"wood_1": 3, "stone_1": 1}`
- `const REFUEL_COST := {"wood_1": 2}`
- `const REFUEL_SECONDS := 120.0`
- `const MAX_REMAINING_SECONDS := 600.0`
- `const REFUEL_RANGE := 3.2`
- `const DURATION := 300.0`
- `const WARM_RADIUS := 5.0`
- `const BUILD_RANGE := 4.0`
- `const MIN_DISTANCE := 1.7`
- `const MIN_SEPARATION := 2.5`
- `const MAX_GLOBAL := 96`
- `const MAX_PER_OWNER := 2`
- `const CAMP_RADIUS := 0.45`
- `const STORM_BURN_MULTIPLIER := 2.0`

## Functions

### `storm_extra_fuel`

```gdscript
static func storm_extra_fuel(delta: float, weather: Dictionary) -> float
```

Ordinary time already burns one second of fuel per server second.
The storm penalty only applies to the extra second; invalid input is safe.

### `valid_site`

```gdscript
static func valid_site(world, point: Vector2, from: Vector2, campfires: Dictionary) -> String
```

### `refuel_reason`

```gdscript
static func refuel_reason(camp: Dictionary, position: Vector3, now: float) -> String
```

Any living survivor can contribute wood to a nearby shared campfire.
Refusing when fewer than two minutes fit prevents charging for almost no heat.

### `has_warmth`

```gdscript
static func has_warmth(campfires: Dictionary, position: Vector3, now: float) -> bool
```

### `visible`

```gdscript
static func visible(campfires: Dictionary, position: Vector3, now: float, radius: float) -> Array
```

