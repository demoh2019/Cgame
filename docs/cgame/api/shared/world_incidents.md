# world_incidents.gd

> Random world incidents that keep the map alive between the big timed events: a wandering horde drawn toward a survivor, a survivors' cache under guard, and a...

`res://scripts/shared/world_incidents.gd`

## Overview

Random world incidents that keep the map alive between the big timed events:
a wandering horde drawn toward a survivor, a survivors' cache under guard, and a
screamer with an escort. The server picks the moment, the place and every spawn;
clients only hear about it (event "incident") and see the infected and the cache.

## Constants

- `const INTERVAL_MIN := 90.0`
- `const INTERVAL_MAX := 150.0`
- `const RETRY_SECONDS := 20.0`
- `const MAX_ACTIVE_INFECTED := 150 # Incidents never push the server past this many infected.`
- `const MIN_DISTANCE := 40.0`
- `const MAX_DISTANCE := 70.0`
- `const KINDS := ["horde", "cache", "screamer"]`

## Functions

### `next_delay`

```gdscript
static func next_delay(rng: RandomNumberGenerator) -> float
```

### `pick_kind`

```gdscript
static func pick_kind(rng: RandomNumberGenerator) -> String
```

### `site_near`

```gdscript
static func site_near(world, around: Vector3, rng: RandomNumberGenerator) -> Dictionary
```

A dry, walkable, non-safe spot 40-70 m from the survivor, or {} when none is found.

### `roster`

```gdscript
static func roster(kind: String, zone: int, rng: RandomNumberGenerator) -> Array
```

Infected types for an incident in a zone. Deterministic for the given rng.

