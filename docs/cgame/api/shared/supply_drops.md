# supply_drops.gd

> Dangerous-zone public supply drops.

`res://scripts/shared/supply_drops.gd`

## Overview

Dangerous-zone public supply drops. The server decides sites, tiers and rewards.
No scene physics or client RPC is needed: drops use existing loot bags and snapshots.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")`
- `const INTERVAL_SECONDS := 300.0`
- `const RETRY_SECONDS := 60.0`
- `const LIFETIME_SECONDS := 420.0`
- `const MIN_DISTANCE := 32.0`
- `const MAX_DISTANCE := 54.0`
- `const SITE_ATTEMPTS := 24`
- `const Movement = preload("res://scripts/shared/movement.gd")`
- `const MAX_GUARDS := 3`
- `const MAX_ACTIVE_INFECTED := 90`
- `const MIN_SURVIVOR_DISTANCE := 12.0`
- `const MIN_INFECTED_DISTANCE := 3.5`
- `const MIN_GUARD_SEPARATION := 5.0`
- `const GUARD_RADII := [8.0, 11.0, 14.0]`
- `const GUARD_ANGLES := 16`
- `const GUARD_GRID_HALF := Vector2(12.0, 12.0)`
- `const GUARD_GRID_SPACING := 6.0`
- `const GUARD_GRID_SAMPLES := 25 # Bounded 5x5 fallthrough when all rings are blocked.`

## Functions

### `site_near`

```gdscript
static func site_near(world, player_position: Vector3, rng: RandomNumberGenerator) -> Dictionary
```

Pick dry, walkable ground close enough for interest-management visibility.
Returns an empty dictionary rather than dropping loot in water or protected zones.

### `loot_for_zone`

```gdscript
static func loot_for_zone(zone: int, rng: RandomNumberGenerator) -> Dictionary
```

Bounded, known inventory IDs; there are no client-supplied reward amounts.

### `living_guards`

```gdscript
static func living_guards(bag: Dictionary, infected: Dictionary) -> int
```

IDs are server-only and absent from client snapshots. Ordinary bags are unaffected.

### `mark_cleared`

```gdscript
static func mark_cleared(bag: Dictionary, infected: Dictionary) -> bool
```

Release is one-shot and only after the LAST real escort is defeated.
The public cache remains available to any survivor; no killer owns it.
The original escort count prevents unguarded caches from faking an event.

### `guard_types`

```gdscript
static func guard_types(zone: int) -> Array[String]
```

### `guard_grid_candidates`

```gdscript
static func guard_grid_candidates(center: Vector2, survivors: Array[Vector3], prefer_native: bool = true) -> PackedVector2Array
```

A context-relative 5x5 backup search. Never trusts client coordinates.
Direction points AWAY from the closest finite survivor; ties use X/Z.

### `guard_sites`

```gdscript
static func guard_sites(world, site: Dictionary, survivors: Array[Vector3], infected: Dictionary, capacity: int, angle_offset: int = 0) -> Array[Dictionary]
```

Validate positions against server-owned player/zombie locations and collisions.
Bad terrain or a nearby survivor reduces guards rather than spawning on top
of somebody. The bounded angular search is deterministic for replay/tests.

_1 private function(s) starting with `_` are not listed._
