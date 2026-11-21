# trade_journal.gd

> Durable inventory transaction journal for two-account deals (trades and market sales).

`res://scripts/server/trade_journal.gd`

## Overview

Durable inventory transaction journal for two-account deals (trades and
market sales). Redo log with after-images: the post-deal snapshots of both
characters are fsynced to disk BEFORE the atomic Nakama pair commit, so a
server crash between "deal done in memory" and "backend confirmed" can be
replayed on restart with the same transaction id (the backend dedupes it).

A side is "superseded" once a later save of that account succeeded: its
snapshot is older than the backend and must never be written back. Replay
then settles only the side(s) that are still newest.

## Constants

- `const VERSION := 1`
- `const MAX_ENTRIES := 256`

## Functions

### `open_file`

```gdscript
func open_file(journal_path: String) -> bool
```

### `valid_entry`

```gdscript
static func valid_entry(entry: Variant) -> bool
```

### `record`

```gdscript
func record(tx: String, user_a: String, data_a: Dictionary, user_b: String, data_b: Dictionary) -> bool
```

Write-ahead: returns false if the deal could not be made durable.

### `settle`

```gdscript
func settle(tx: String) -> void
```

The backend confirmed the deal (or a replay settled it).

### `supersede`

```gdscript
func supersede(user_id: String) -> void
```

A newer single-account save landed: that side's journaled snapshot is stale.

### `replay_kind`

```gdscript
static func replay_kind(entry: Dictionary) -> String
```

Replay plan: "pair" when both sides are newest, else "single" for the live side.

### `accounts`

```gdscript
func accounts() -> PackedStringArray
```

_2 private function(s) starting with `_` are not listed._
