# server_tick_governor.gd

> Server-only CPU tick telemetry and conservative encounter backpressure.

`res://scripts/server/server_tick_governor.gd`

## Overview

Server-only CPU tick telemetry and conservative encounter backpressure.
Existing actors still simulate every tick; only future random incident
reinforcements are reduced on sustained overload.

## Constants

- `const HISTORY_CAP: int = 200`
- `const WINDOW_TICKS: int = 20`
- `const MIN_SPAWN_CAP: int = 2`
- `const MAX_SPAWN_CAP: int = 10`
- `const TARGET_TICK_MS: float = 50.0 # GameServer runs at Defs.TICK_RATE = 20.`
- `const HIGH_RATIO: float = 0.90`
- `const LOW_RATIO: float = 0.60`
- `const HIGH_WINDOWS: int = 3`
- `const LOW_WINDOWS: int = 5`

## Functions

### `observe_tick`

```gdscript
func observe_tick(elapsed_usec: int, active_players: int) -> void
```

Called by the dedicated server after the *authoritative network+simulation
tick*, before optional disk checkpoint work. Invalid samples are ignored.

### `set_enabled`

```gdscript
func set_enabled(value: bool) -> void
```

### `get_budget_units`

```gdscript
func get_budget_units() -> int
```

Shared read-only budget API with Cgame's native AdaptiveTickGovernor.

### `history_count`

```gdscript
func history_count() -> int
```

### `samples_oldest_first`

```gdscript
func samples_oldest_first() -> Array[float]
```

### `snapshot`

```gdscript
func snapshot() -> Dictionary
```

### `percentile_nearest_rank`

```gdscript
static func percentile_nearest_rank(samples: Array[float], percentile: float) -> float
```

Deterministic nearest-rank p95; never mutates caller's samples.

