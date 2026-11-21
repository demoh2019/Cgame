# rollback_debugger.gd

> Debug view over a RollbackNetcode: records every rollback (from/to frame, resimulated frames, the player whose late input caused it), per-player prediction m...

`res://scripts/shared/rollback_debugger.gd`

## Overview

Debug view over a RollbackNetcode: records every rollback (from/to frame, resimulated
frames, the player whose late input caused it), per-player prediction miss rate, desync
frames with a state diff, and a text report.

Drive the netcode THROUGH this wrapper (add_remote_input / advance / process) so inputs
can be classified; the netcode itself is not modified. Original GDScript, no third-party code.

## Constants

- `const HISTORY_LIMIT: int = 128`

## Functions

### `attach`

```gdscript
func attach(p_net: RefCounted) -> void
```

### `add_remote_input`

```gdscript
func add_remote_input(pid: Variant, f: int, input: Dictionary) -> void
```

### `add_local_input`

```gdscript
func add_local_input(pid: Variant, input: Dictionary) -> int
```

### `advance`

```gdscript
func advance() -> bool
```

### `process`

```gdscript
func process() -> void
```

### `miss_rate`

```gdscript
func miss_rate(pid: Variant) -> float
```

Miss rate for a player: mispredicted / late inputs (0.0 when none arrived late).

### `attach_remote_state`

```gdscript
func attach_remote_state(frame: int, remote_state: Dictionary) -> Array
```

Provide the remote peer's state for a desync frame to compute the key-path diff.

### `diff_states`

```gdscript
static func diff_states(a: Variant, b: Variant, path: String = "") -> Array
```

Key paths (e.g. "players.1.x", "items[2]") at which a and b differ, sorted.

### `report`

```gdscript
func report() -> String
```

### `state_history`

```gdscript
func state_history(frame: int) -> Dictionary
```

State recorded when `frame` was reached (may be mispredicted if a rollback followed), or {}.

_4 private function(s) starting with `_` are not listed._
