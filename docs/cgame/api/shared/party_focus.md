# party_focus.gd

> Server-owned coordinated infected focus for classless survivor parties.

`res://scripts/shared/party_focus.gd`

## Overview

Server-owned coordinated infected focus for classless survivor parties.
All spatial checks use live entity positions; clients send no enemy ID.

## Constants

- `const RANGE := 24.0`
- `const HEIGHT_LIMIT := 4.0`
- `const DURATION := 18.0`
- `const COOLDOWN := 28.0`
- `const DAMAGE_BONUS := 0.08`

## Functions

### `in_range`

```gdscript
static func in_range(source: Vector3, target: Vector3) -> bool
```

### `damage`

```gdscript
static func damage(base: float, qualified: bool) -> float
```

Called only for already-authorized server-side infected attacks.

