# siege_outbox.gd

> Crash-recoverable write-ahead outbox for server-authoritative guild siege wins.

`res://scripts/server/siege_outbox.gd`

## Overview

Crash-recoverable write-ahead outbox for server-authoritative guild siege wins.
Append is committed to user:// before the first Nakama RPC attempt.
Acknowledgement removes an entry only after Nakama confirms its receipt.
One dedicated server process must own the outbox path (no shared writers).

## Constants

- `const WorldPersistence = preload("res://scripts/server/world_persistence.gd")`
- `const VERSION := 1`
- `const MAX_RECORDS := 512`
- `const MAX_BYTES := 131072`
- `const MAX_SITE_ID := 25`

## Functions

### `valid_record`

```gdscript
static func valid_record(record: Variant, seed: int) -> bool
```

### `snapshot`

```gdscript
func snapshot() -> Array[Dictionary]
```

### `open_file`

```gdscript
func open_file(new_path: String, seed: int) -> bool
```

Returns false (fail closed) on malformed, oversized or cross-seed files.
Missing file means a new clean journal. Never silently reset corruption.

### `enqueue`

```gdscript
func enqueue(record: Dictionary) -> bool
```

### `acknowledge`

```gdscript
func acknowledge(event_id: String) -> bool
```

Return false on IO errors so a confirmed receipt stays on disk and is
safely replayed with its original ID after a restart.

_3 private function(s) starting with `_` are not listed._
