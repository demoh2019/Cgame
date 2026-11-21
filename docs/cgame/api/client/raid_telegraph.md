# raid_telegraph.gd

> Read-only presentation of server-authoritative raid boss ground slam.

`res://scripts/client/raid_telegraph.gd`

## Overview

Read-only presentation of server-authoritative raid boss ground slam.
Never sends collision, hit or position requests; the server owns damage.

## Constants

- `const MAX_RADIUS := 16.0`
- `const MAX_WARNING_SECONDS := 5.0`

## Functions

### `consume`

```gdscript
func consume(event: Dictionary, world) -> bool
```

Only bounded authoritative warning events may activate the danger circle.
Terminal event IDs must match; stale events cannot erase a newer warning.

### `update_interrupt`

```gdscript
func update_interrupt(progress: Dictionary) -> bool
```

Consumes only the sanitized party-only fields from a server snapshot.
A wrong encounter or malformed tally cannot replace a valid display.

### `clear`

```gdscript
func clear() -> void
```

_4 private function(s) starting with `_` are not listed._
