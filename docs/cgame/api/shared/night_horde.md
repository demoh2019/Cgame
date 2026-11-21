# night_horde.gd

> (no header comment)

`res://scripts/shared/night_horde.gd`

## Constants

- `const Movement = preload("res://scripts/shared/movement.gd")` - Limited night PvPvE horde for dangerous red/black regions. Server-only IDs and bounded, deterministic terrain-safe spawn search.
- `const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")`
- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const CHECK_EVERY_TICKS := 20`
- `const START_DELAY := 480.0`
- `const COOLDOWN_SECONDS := 480.0`
- `const RETRY_SECONDS := 60.0`
- `const MAX_DURATION := 300.0`
- `const CACHE_DURATION := 240.0`
- `const MAX_ACTIVE_INFECTED := 90`
- `const MIN_PLAYER_SEPARATION := 12.0`
- `const MAX_PLAYER_DISTANCE := 30.0`
- `const MIN_INFECTED_SEPARATION := 3.5`
- `const MIN_SPAWN_SEPARATION := 5.0`
- `const RADII := [18.0, 22.0, 26.0]`
- `const ANGLES := 16`
- `const SCATTER_COUNT := 32`
- `const GOLDEN_ANGLE := 2.39996322972865332 # Same fixed constant as native C++.`

## Functions

### `kinds`

```gdscript
static func kinds(zone: int) -> Array[String]
```

### `scatter_candidates`

```gdscript
static func scatter_candidates(center: Vector2, offset: int = 0, prefer_native: bool = true) -> PackedVector2Array
```

Low-correlation fallback candidates across the full horde annulus.
Phase is derived from the same server-owned integer offset as the rings.
No RNG is consumed; every returned point is still untrusted geometry.

### `sites`

```gdscript
static func sites(world, origin: Vector3, survivors: Array[Vector3], infected: Dictionary, capacity: int, offset: int = 0) -> Array[Dictionary]
```

### `fully_defeated`

```gdscript
static func fully_defeated(ids: Array, infected: Dictionary) -> bool
```

A missing/despawned enemy is NOT a legitimate combat victory.

### `loot`

```gdscript
static func loot(zone: int) -> Dictionary
```

_1 private function(s) starting with `_` are not listed._
