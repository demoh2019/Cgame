# threat.gd

> A small bounded server-only PvE hate list (MMORPG tank/aggro rules).

`res://scripts/shared/threat.gd`

## Overview

A small bounded server-only PvE hate list (MMORPG tank/aggro rules).
Players cannot send threat values over RPC; only confirmed zombie damage
records threat. Entries are temporary and never persisted to characters.

## Constants

- `const MAX_TARGETS := 5`
- `const MAX_VALUE := 10000.0`
- `const DECAY_PER_SECOND := 0.75`
- `const SWITCH_MARGIN := 1.25`

## Functions

### `has_native`

```gdscript
static func has_native() -> bool
```

### `record`

```gdscript
static func record(entries: Dictionary, peer_id: int, damage: float) -> bool
```

### `scale`

```gdscript
static func scale(entries: Dictionary, peer_id: int, factor: float) -> bool
```

Reduce a single actor's existing server-authoritative threat.
Never fabricates new aggro. The fallback works on ordinary Godot.

### `decay`

```gdscript
static func decay(entries: Dictionary, delta: float) -> void
```

### `pick`

```gdscript
static func pick(entries: Dictionary, players: Dictionary, origin: Vector2, leash: float, current_target: int = -1) -> int
```

