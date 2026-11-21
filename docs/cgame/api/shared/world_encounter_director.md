# world_encounter_director.gd

> Adaptive PvE incident budgeting for the authoritative GameServer.

`res://scripts/shared/world_encounter_director.gd`

## Overview

Adaptive PvE incident budgeting for the authoritative GameServer.
Inspired by encounter directors, but deliberately deterministic and bounded.
No client-supplied values, persistent state, physics queries or extra RNG.

## Constants

- `const WorldIncidents = preload("res://scripts/shared/world_incidents.gd")`
- `const LOCAL_RADIUS: float = 75.0`
- `const LOCAL_HARD_CAP: int = 20`
- `const LOCAL_SOFT_CAP: int = 8`
- `const LOCAL_DENSE_CAP: int = 12`
- `const MINIMUM_HEALTH_RATIO: float = 0.0`
- `const MAXIMUM_HEALTH_RATIO: float = 1.0`
- `const MAX_SQUAD: int = 10`

## Functions

### `nearby_infected`

```gdscript
static func nearby_infected(zombies: Dictionary, center: Vector3) -> int
```

Counts living enemies in a bounded radius. Early exit avoids scanning the
rest of the world after the local crowd has saturated the encounter.

### `spawn_budget`

```gdscript
static func spawn_budget(total_infected: int, nearby: int, health_ratio: float, zone: int) -> int
```

Server-owned budget is the minimum of local pressure, health sensitivity,
zone difficulty and the global infected cap. Invalid state fails closed.

### `bounded_roster`

```gdscript
static func bounded_roster(roster: Array, limit: int) -> Array
```

Keeps encounter identity (howler, elite cache guard, etc.) at the front.
Does not mutate the upstream roster or call RandomNumberGenerator.

### `respite_seconds`

```gdscript
static func respite_seconds(base_delay: float, nearby: int, health_ratio: float) -> float
```

Extra recovery when crowds are building or survivors are badly hurt.
No shorter-than-original cooldowns and no client-side difficulty controls.

