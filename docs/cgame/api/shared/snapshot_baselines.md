# snapshot_baselines.gd

> Per-client baseline tracker (Quake 3 netchan / Source delta snapshots / UE Iris): deltas are built against the last state the client acknowledged, so a lost ...

`res://scripts/shared/snapshot_baselines.gd`

## Overview

Per-client baseline tracker (Quake 3 netchan / Source delta snapshots / UE Iris):
deltas are built against the last state the client acknowledged, so a lost packet
only means the next delta is larger, never a desync.

## Constants

- `const SnapshotDelta = preload("res://scripts/shared/snapshot_delta.gd")`
- `const MAX_UNACKED := 32`

## Functions

### `record_sent`

```gdscript
func record_sent(client_id: int, sequence: int, state: Dictionary) -> void
```

### `acknowledge`

```gdscript
func acknowledge(client_id: int, sequence: int) -> void
```

### `baseline_for`

```gdscript
func baseline_for(client_id: int) -> Dictionary
```

### `build_packet`

```gdscript
func build_packet(client_id: int, sequence: int, state: Dictionary, tolerances: Dictionary = {}) -> Dictionary
```

### `forget`

```gdscript
func forget(client_id: int) -> void
```

_1 private function(s) starting with `_` are not listed._
