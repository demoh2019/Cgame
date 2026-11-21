# outpost_fortification.gd

> Siege fortification costs and capture difficulty for party-owned outposts.

`res://scripts/shared/outpost_fortification.gd`

## Overview

Siege fortification costs and capture difficulty for party-owned outposts.
Only the authoritative game server can call fortify() with player inventory.
This uses no asynchronous work: checking, spending and upgrade are one tick.

## Constants

- `const MAX_LEVEL := 3`
- `const BUILD_RADIUS := 4.0`
- `const EXTRA_CAPTURE_SECONDS_PER_LEVEL := 10.0`
- `const COSTS := [`

## Functions

### `cost_for_level`

```gdscript
static func cost_for_level(level: int) -> Dictionary
```

### `capture_duration`

```gdscript
static func capture_duration(base_duration: float, level: int) -> float
```

### `fortify`

```gdscript
static func fortify(site: Dictionary, inventory, group_id: int, position: Vector3, now: float, contested_now: bool) -> Dictionary
```

Returns the result without changing state unless everything is valid.
A contested point cannot be reinforced, even if the previous tick's
client-visible contested flag has not yet changed.

