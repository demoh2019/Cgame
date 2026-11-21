# lag_compensation.gd

> Server-side lag compensation (Source engine / Overwatch / UE5 rewind): a short history of every survivor's position lets the server judge a PvP swing or shot...

`res://scripts/server/lag_compensation.gd`

## Overview

Server-side lag compensation (Source engine / Overwatch / UE5 rewind):
a short history of every survivor's position lets the server judge a PvP
swing or shot against where the target was on the attacker's screen,
i.e. half the round trip plus the client's interpolation delay ago.
Rewind is capped so high-ping players cannot hit around corners.

## Constants

- `const HISTORY_SECONDS := 0.5`
- `const MAX_REWIND := 0.25`
- `const CLIENT_INTERPOLATION := 0.12 # network_jitter_buffer.gd BASE_DELAY.`

## Functions

### `record`

```gdscript
func record(id: int, now: float, position: Vector3) -> void
```

### `forget`

```gdscript
func forget(id: int) -> void
```

### `prune`

```gdscript
func prune(alive_ids: Dictionary) -> void
```

### `rewind_for`

```gdscript
static func rewind_for(round_trip: float) -> float
```

How far back to judge an attacker with this round-trip time (seconds).

### `position_at`

```gdscript
func position_at(id: int, at: float, fallback: Vector3) -> Vector3
```

Interpolated position at `at`; `fallback` when no usable history exists.

