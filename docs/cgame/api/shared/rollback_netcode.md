# rollback_netcode.gd

> Rollback netcode core (GGPO-style): input ring buffers, local prediction, confirmed-frame tracking, rollback + resimulation, bounded snapshot ring, per-frame...

`res://scripts/shared/rollback_netcode.gd`

## Overview

Rollback netcode core (GGPO-style): input ring buffers, local prediction, confirmed-frame
tracking, rollback + resimulation, bounded snapshot ring, per-frame checksums with desync
detection, input delay and a max prediction window (stalls when exceeded).

Design source: Tony Cannon's GGPO write-ups / the public rollback-netcode literature and
Glenn Fiedler's "Deterministic Lockstep" article (ideas only). No third-party code was
copied; this is an independent reimplementation (no license obligations, no Apache-2.0
notice needed).

Contract: step is a pure deterministic Callable(state: Dictionary, inputs: Dictionary,
dt: float) -> Dictionary. `inputs` maps player_id -> input (Dictionary) in sorted player
order. The step receives a deep copy and may mutate it and return it.

Frame semantics: snapshot[f] is the state at the START of frame f (before f's inputs).
advance() simulates the current frame f -> f+1. A frame is "confirmed" once real inputs of
every player are known for it and all earlier frames.

Transport glue (caller): send drain_outgoing() entries to peers, feed received entries to
add_remote_input(), optionally exchange get_checksum_report() and feed add_remote_checksum().

## Constants

- `const MAX_FINAL_CHECKSUMS: int = 256`
- `const MAX_SCAN_BACK: int = 512`

## Signals

- `signal desync_detected(frame: int, local_checksum: int, remote_checksum: int)`

## Functions

### `setup`

```gdscript
func setup(p_step: Callable, p_initial_state: Dictionary, p_players: Array, p_local_players: Array, p_dt: float = 1.0 / 60.0, p_input_delay: int = 0, p_max_prediction: int = 8, p_snapshot_capacity: int = 0) -> void
```

### `state_checksum`

```gdscript
static func state_checksum(s: Dictionary) -> int
```

### `add_local_input`

```gdscript
func add_local_input(pid: Variant, input: Dictionary) -> int
```

Schedules `input` for frame (current local frame + input_delay). Returns that frame.

### `add_remote_input`

```gdscript
func add_remote_input(pid: Variant, f: int, input: Dictionary) -> void
```

Feeds a remote player's real input for `f`. Duplicates and stale frames are ignored.

### `drain_outgoing`

```gdscript
func drain_outgoing() -> Array
```

Entries {player, frame, input} for local inputs not yet drained (includes delay prefill).

### `add_remote_checksum`

```gdscript
func add_remote_checksum(f: int, checksum: int) -> void
```

### `get_checksum_report`

```gdscript
func get_checksum_report() -> Array
```

New {frame, checksum} reports for frames that became final since the last call.

### `advance`

```gdscript
func advance() -> bool
```

Applies a pending rollback (if any), then simulates one frame. False when stalled.

### `process`

```gdscript
func process() -> void
```

Resolves a pending rollback caused by late/corrected inputs.

### `is_stalled`

```gdscript
func is_stalled() -> bool
```

### `rollback_to`

```gdscript
func rollback_to(f: int) -> bool
```

Restores the snapshot at `f` and resimulates up to the current frame. False if `f` is
outside the snapshot ring or in the future.

### `snapshot_count`

```gdscript
func snapshot_count() -> int
```

### `get_state`

```gdscript
func get_state() -> Dictionary
```

### `checksum_of`

```gdscript
func checksum_of(f: int) -> int
```

Checksum of the state at the start of `f` (current or final), or 0 if unknown.

### `has_desync`

```gdscript
func has_desync() -> bool
```

### `input_for`

```gdscript
func input_for(pid: Variant, f: int) -> Dictionary
```

Input that was/will be used for (pid, f): real if known, else predicted (repeat last).

### `has_real_input`

```gdscript
func has_real_input(pid: Variant, f: int) -> bool
```

_6 private function(s) starting with `_` are not listed._
