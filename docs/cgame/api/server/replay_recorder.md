# replay_recorder.gd

> Deterministic session recorder / replayer for the authoritative server.

`res://scripts/server/replay_recorder.gd`

## Overview

Deterministic session recorder / replayer for the authoritative server.

Records the inputs of a session (seed, world seed, initial players and, per tick, the
delta plus every command) and re-runs them on a fresh server, returning a state hash per
tick. Two runs of the same recording must produce identical hash lists; the first
differing tick (see compare) pinpoints a determinism bug or a tampered recording.

Technique credit: input-log deterministic replay and per-frame state checksums as used by
lockstep/rollback engines (e.g. GGPO, MIT, https://github.com/pond3r/ggpo; Factorio-style
desync detection). The state hash is 64-bit FNV-1a (public domain, Fowler/Noll/Vo).
This file is original GDScript; no third-party code was copied.

Only methods named "cmd_*" (client commands) and "submit_input" (the movement input path,
which is not a cmd_ method in this server) may be replayed. Everything else (add_player,
tick, restore, ...) is refused so a replay file cannot drive privileged server entry points.

## Constants

- `const WorldPersistence = preload("res://scripts/server/world_persistence.gd")`
- `const FORMAT_VERSION := 1`
- `const FNV_OFFSET := -3750763034362895579 # 0xcbf29ce484222325 as signed int64`
- `const FNV_PRIME := 0x100000001b3`

## Functions

### `add_initial_player`

```gdscript
func add_initial_player(peer: int, p_name: String) -> void
```

### `record_command`

```gdscript
func record_command(peer: int, method: String, args: Array = []) -> bool
```

Queues a command for the tick being recorded. Refused methods return false.

### `end_tick`

```gdscript
func end_tick(delta: float) -> void
```

Closes the current tick with the delta passed to server.tick().

### `is_allowed_method`

```gdscript
static func is_allowed_method(method: String) -> bool
```

### `to_dict`

```gdscript
func to_dict() -> Dictionary
```

### `save`

```gdscript
func save(path: String) -> bool
```

### `load`

```gdscript
static func load(path: String) -> Dictionary
```

Returns the replay Dictionary, or {} when missing / malformed.

### `play`

```gdscript
static func play(replay: Dictionary, make_server: Callable) -> Dictionary
```

Re-runs a replay on make_server.call(seed, world_seed) -> GameServer.
Returns {"hashes": Array (one int per tick), "rejected": Array[String], "ok": bool}.

### `state_hash`

```gdscript
static func state_hash(server) -> int
```

64-bit FNV-1a over a canonical (sorted-key) projection of the gameplay-relevant state.

### `compare`

```gdscript
static func compare(a_hashes: Array, b_hashes: Array) -> int
```

First tick index at which two hash lists differ (a length mismatch counts), else -1.

_2 private function(s) starting with `_` are not listed._
