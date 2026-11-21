# raid_encounter.gd

> One server-owned group boss in dangerous zones.

`res://scripts/shared/raid_encounter.gd`

## Overview

One server-owned group boss in dangerous zones. Not a second zombie AI:
uses the existing Zombie brain, threat table and combat/loot paths.
No RPC can ask for a spawn, a slam, a prize or a cooldown reset.

## Constants

- `const Movement = preload("res://scripts/shared/movement.gd")`
- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const MIN_ZONE := 2`
- `const MIN_PARTICIPANTS := 2`
- `const MAX_INFECTED := 90`
- `const START_DELAY := 90.0`
- `const COOLDOWN := 600.0`
- `const MAX_ENCOUNTER_SECONDS := 240.0`
- `const RALLY_RANGE := 20.0`
- `const SPAWN_RADII := [22.0, 26.0, 30.0]`
- `const SPAWN_ANGLES := 12`
- `const MIN_SPAWN_TO_PLAYER := 12.0`
- `const MIN_SPAWN_TO_LEADER := 18.0`
- `const MAX_SPAWN_TO_LEADER := 32.0`
- `const BOSS_HEALTH := 600.0`
- `const BOSS_DAMAGE := 30.0`
- `const BOSS_MASTERY_XP := 80`
- `const SLAM_RADIUS := 5.0`
- `const SLAM_DAMAGE := 34.0`
- `const SLAM_WARNING := 2.0`
- `const SLAM_COOLDOWN := 14.0`
- `const ENRAGE_HEALTH_FRACTION := 0.35`
- `const ENRAGE_MELEE_MULTIPLIER := 1.35`
- `const ENRAGE_SLAM_DAMAGE := 44.0`
- `const ENRAGE_SLAM_COOLDOWN := 8.0`

## Functions

### `eligible_leader`

```gdscript
static func eligible_leader(world, players: Dictionary, parties) -> int
```

### `spawn_site`

```gdscript
static func spawn_site(world, players: Dictionary, leader: Vector3, offset: int = 0) -> Vector2
```

A deterministic bounded search instead of spawning enemies in players,
walls, water, safe hubs, or across a risk-zone boundary.

### `empower`

```gdscript
static func empower(boss) -> void
```

### `try_enrage`

```gdscript
static func try_enrage(boss) -> bool
```

Only an alive, server-owned raid boss may enter phase two.
Its own stats dictionary is cloned, so unrelated brutes stay unchanged.

### `slam_cooldown`

```gdscript
static func slam_cooldown(boss) -> float
```

### `slam_damage`

```gdscript
static func slam_damage(boss) -> float
```

### `treasure`

```gdscript
static func treasure(zone: int) -> Dictionary
```

### `in_slam`

```gdscript
static func in_slam(center: Vector2, victim: Vector3) -> bool
```

