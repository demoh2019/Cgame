# ambient_tick_budget.gd

> Budgeted cosmetic update dispatcher for the game client.

`res://scripts/client/ambient_tick_budget.gd`

## Overview

Budgeted cosmetic update dispatcher for the game client.
No Node references, world writes or network simulation are stored here.
Each lane accumulates elapsed time while skipped and receives a bounded dt
when scheduled, so all presentation work stays on the main thread.

## Constants

- `const LANES := ["dragonflies", "dust_devils", "tumbleweeds", "dusk_bats"]`
- `const HZ_BY_QUALITY := [12.0, 18.0, 30.0, 60.0]`
- `const MAX_STEP := 0.16`

## Functions

### `begin_frame`

```gdscript
func begin_frame(delta: float, quality: int) -> void
```

### `consume`

```gdscript
func consume(lane: String, delta: float, force: bool = false) -> float
```

Returns 0 when the lane should not be updated this frame, or the
accumulated elapsed time when an update is due. A visibility transition
always takes effect immediately even if the per-frame budget is exhausted.

### `reset`

```gdscript
func reset() -> void
```

### `updated_total`

```gdscript
func updated_total() -> int
```

### `skipped_total`

```gdscript
func skipped_total() -> int
```

### `current_budget`

```gdscript
func current_budget() -> int
```

### `pressure_percent`

```gdscript
func pressure_percent() -> float
```

### `last_frame_counts`

```gdscript
func last_frame_counts() -> Vector2i
```

### `set_frame_time_budget_us`

```gdscript
func set_frame_time_budget_us(budget_us: int) -> bool
```

Zero disables the CPU time cap; a positive limit is a soft upper bound.

### `get_frame_time_budget_us`

```gdscript
func get_frame_time_budget_us() -> int
```

### `record_cost`

```gdscript
func record_cost(lane: String, elapsed_us: int) -> bool
```

### `set_lane_rate_scale`

```gdscript
func set_lane_rate_scale(lane: String, scale: float) -> bool
```

Rate controls how soon a lane becomes eligible. Importance controls how
urgent it is once due; the two settings deliberately remain independent.

### `get_lane_rate_scale`

```gdscript
func get_lane_rate_scale(lane: String) -> float
```

### `set_lane_max_deferred_frames`

```gdscript
func set_lane_max_deferred_frames(lane: String, frames: int) -> bool
```

A soft deferral deadline only changes which already-due lane is reserved.
Zero disables it; global per-frame slots and measured CPU caps stay intact.

### `get_lane_max_deferred_frames`

```gdscript
func get_lane_max_deferred_frames(lane: String) -> int
```

### `get_deadline_overdue_lane_count`

```gdscript
func get_deadline_overdue_lane_count() -> int
```

### `rate_scale_for_importance`

```gdscript
static func rate_scale_for_importance(importance: float) -> float
```

Deterministic mapping of existing scene importance to a conservative rate.
0.25 -> 0.75x, 1.0 -> 1.0x, 4.0 -> 1.5x. No per-frame allocations.

### `deadline_frames_for_importance`

```gdscript
static func deadline_frames_for_importance(importance: float) -> int
```

Only currently significant ambient effects receive a short deadline.

### `set_lane_importance`

```gdscript
func set_lane_importance(lane: String, importance: float) -> bool
```

### `get_lane_importance`

```gdscript
func get_lane_importance(lane: String) -> float
```

### `get_lane_last_frame_cost_us`

```gdscript
func get_lane_last_frame_cost_us(lane: String) -> int
```

Caller-measured CPU microseconds from the previous completed frame.

### `get_lane_estimated_cost_us`

```gdscript
func get_lane_estimated_cost_us(lane: String) -> int
```

### `get_reserved_estimated_cost_us`

```gdscript
func get_reserved_estimated_cost_us() -> int
```

### `suggested_importance`

```gdscript
static func suggested_importance(daylight: float, storming: bool, underground: bool) -> Dictionary
```

Scene relevance weights are independent of the server simulation.

### `current_frame_cost_us`

```gdscript
func current_frame_cost_us() -> int
```

### `last_frame_cost_us`

```gdscript
func last_frame_cost_us() -> int
```

_1 private function(s) starting with `_` are not listed._
