# caravan_ambush.gd

> (no header comment)

`res://scripts/shared/caravan_ambush.gd`

## Constants

- `const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")` - Trade routes through red/black full-loot land attract finite infected waves. All prerequisites are checked from the real server-owned character, backpack and world position. One encounter per active route survives relogging.
- `const NightHorde = preload("res://scripts/shared/night_horde.gd")`
- `const CHECK_EVERY_TICKS := 20`
- `const MAX_ACTIVE_INFECTED := 85`
- `const MAX_ACTIVE_WAVES := 4`
- `const LIFETIME_SECONDS := 190.0`
- `const MIN_TRAVEL_METERS := 80.0`
- `const ROUTE_PROGRESS := 0.35`
- `const DESTINATION_CLEARANCE := 32.0`

## Functions

### `eligible`

```gdscript
static func eligible(world, player_position: Vector3, route: Dictionary, carried_count: int, completed: bool, alive: bool) -> bool
```

### `placement`

```gdscript
static func placement(world, origin: Vector3, survivors: Array[Vector3], infected: Dictionary, capacity: int, seed_angle: int) -> Array[Dictionary]
```

Reuse existing terrain-safe NightHorde placements, but never create the
public horde trophy or another independent loot reward.

### `record_kill`

```gdscript
static func record_kill(wave: Dictionary, infected_id: int) -> bool
```

Every summoned enemy ID must receive a real server kill callback. Despawned
or missing enemies do not count toward the courier's earned defense bonus.

### `defense_bonus`

```gdscript
static func defense_bonus(fare: int) -> int
```

A modest NPC risk premium, earned only if the entire genuine wave is cleared.

### `available`

```gdscript
static func available(active_waves: Array, infected: Dictionary) -> int
```

