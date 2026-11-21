# replay_inspector.gd

> Server replay inspector over ReplayRecorder data: tick listing, summary, state at a tick (re-simulated on a fresh server) and hash-list divergence finding.

`res://scripts/server/replay_inspector.gd`

## Overview

Server replay inspector over ReplayRecorder data: tick listing, summary, state at a tick
(re-simulated on a fresh server) and hash-list divergence finding.
Original GDScript, no third-party code.

## Constants

- `const ReplayRecorder = preload("res://scripts/server/replay_recorder.gd")`

## Functions

### `load_file`

```gdscript
func load_file(path: String) -> bool
```

### `load_dict`

```gdscript
func load_dict(data: Dictionary) -> void
```

### `list_ticks`

```gdscript
func list_ticks(only_with_commands: bool = false) -> Array
```

[{tick, delta, command_count, commands}] for every recorded tick.

### `summary`

```gdscript
func summary() -> Dictionary
```

### `state_at`

```gdscript
func state_at(tick: int, make_server: Callable) -> Dictionary
```

Re-simulates ticks 0..tick (inclusive) on make_server.call(seed, world_seed).
Returns {tick, hash, players: {peer: {pos, health}}, zombies, server} or {} on failure.

### `diff_hashes`

```gdscript
static func diff_hashes(a_hashes: Array, b_hashes: Array) -> Dictionary
```

{first, differing: [ticks], length_a, length_b}; first = -1 when identical.

### `find_first_divergence`

```gdscript
func find_first_divergence(rep: Dictionary, make_server: Callable, reference_hashes: Array) -> Dictionary
```

Replays and compares with reference hashes. {tick, expected, actual, commands} (tick -1 = none).

