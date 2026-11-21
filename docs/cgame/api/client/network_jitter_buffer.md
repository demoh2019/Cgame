# network_jitter_buffer.gd

> Adaptive, presentation-only network jitter buffer for simulated proxies.

`res://scripts/client/network_jitter_buffer.gd`

## Overview

Adaptive, presentation-only network jitter buffer for simulated proxies.
Server positions and combat remain authoritative. No future extrapolation.
Arrival timestamps use a monotonic local clock, never FPS or wall time.

## Constants

- `const BASE_DELAY := 0.12`
- `const MAX_DELAY := 0.35`
- `const EXPECTED_SNAPSHOT_STEP := 0.10`
- `const MAX_NETWORK_GAP := 0.65`
- `const MAX_EXTRA := 0.17`
- `const EXTRA_MULTIPLIER := 1.35`
- `const PEAK_RELEASE_PER_SECOND := 0.04`
- `const DELAY_RELEASE_PER_SECOND := 0.03`
- `const MAX_RECOVERY_GUARD_PACKETS := 32`

## Functions

### `configure`

```gdscript
func configure(base_delay: float, max_delay: float, expected_snapshot_step: float) -> bool
```

### `get_stats`

```gdscript
func get_stats() -> Dictionary
```

### `reset`

```gdscript
func reset() -> void
```

### `set_recovery_guard_packets`

```gdscript
func set_recovery_guard_packets(packets: int) -> bool
```

Changes visual jitter decay only; zero preserves existing behavior.
Configuration survives reset, but a pending recovery guard is cleared.

### `get_recovery_guard_packets`

```gdscript
func get_recovery_guard_packets() -> int
```

### `get_recovery_hold_remaining`

```gdscript
func get_recovery_hold_remaining() -> int
```

### `get_estimated_missing_snapshots`

```gdscript
func get_estimated_missing_snapshots() -> int
```

### `get_burst_loss_events`

```gdscript
func get_burst_loss_events() -> int
```

### `observe`

```gdscript
func observe(server_time: float, local_arrival_time: float) -> float
```

Call on the same main thread as EntityView.update_from. Repeated reads of
the same snapshot (render FPS > server tick) never change the delay.

### `advance_clock`

```gdscript
static func advance_clock(render_time: float, newest_time: float, target_delay: float, delta: float, host: Node3D = null) -> float
```

Same deterministic algorithm as Cgame's native Node3D extension, with a
stock-Godot fallback. One policy instance controls all visible actors.

_1 private function(s) starting with `_` are not listed._
