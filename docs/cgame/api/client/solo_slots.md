# solo_slots.gd

> Three independently persisted solo survivors: each has its own character and world checkpoint, graceful-stop signal, and loopback ENet port.

`res://scripts/client/solo_slots.gd`

## Overview

Three independently persisted solo survivors: each has its own character
and world checkpoint, graceful-stop signal, and loopback ENet port.
Slot 1 preserves all paths used by earlier one-survivor versions.

## Constants

- `const SLOT_COUNT := 3`
- `const BASE_PORT := 24566`

## Functions

### `valid`

```gdscript
static func valid(slot: int) -> bool
```

### `port`

```gdscript
static func port(slot: int) -> int
```

### `character_path`

```gdscript
static func character_path(slot: int) -> String
```

### `world_path`

```gdscript
static func world_path(slot: int) -> String
```

### `stop_path`

```gdscript
static func stop_path(slot: int) -> String
```

### `description`

```gdscript
static func description(slot: int) -> String
```

The title screen never parses or trusts saved item contents.
The authoritative solo server validates the full character on join.

