# player_presence_grid.gd

> CPU-side spatial broadphase for server-owned living survivor positions.

`res://scripts/server/player_presence_grid.gd`

## Overview

CPU-side spatial broadphase for server-owned living survivor positions.
Rebuilt once per infected population maintenance pass (~1 second).
Preserves exact XZ distance semantics; no client data or scene nodes.

## Constants

- `const CELL_SIZE: float = 64.0`
- `const DIRECT_SCAN_THRESHOLD: int = 8`
- `const MAX_HASH_QUERY_RADIUS: float = 512.0 # Large generic queries fall back to exact scan.`

## Functions

### `rebuild`

```gdscript
func rebuild(positions: Array[Vector2]) -> void
```

### `any_within`

```gdscript
func any_within(point: Vector2, radius: float, inclusive: bool = true) -> bool
```

Exactly matches a brute-force radius check: 'strict' is used for the
no-spawn radius (<12m); inclusive is used for retention (<=130m).
The direct path saves hashing overhead on solo and small co-op servers.

### `any_within_batch`

```gdscript
func any_within_batch(points: PackedVector2Array, radius: float, inclusive: bool = true) -> PackedByteArray
```

Return one flag per probe, in input order. Invalid points count as misses.
Query/candidate diagnostics follow scalar semantics for reproducible tests.

### `snapshot`

```gdscript
func snapshot() -> Dictionary
```

### `cell_of`

```gdscript
static func cell_of(point: Vector2) -> Vector2i
```

