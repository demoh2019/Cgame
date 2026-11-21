# raid_recovery.gd

> The raid warlord exposes its armor after a confirmed slam.

`res://scripts/shared/raid_recovery.gd`

## Overview

The raid warlord exposes its armor after a confirmed slam.
All timing, target identity and damage decisions are server-authoritative.

## Constants

- `const NORMAL_SECONDS := 4.0`
- `const ENRAGED_SECONDS := 2.5`
- `const DAMAGE_BONUS := 0.15`

## Functions

### `window_seconds`

```gdscript
static func window_seconds(boss) -> float
```

### `remaining`

```gdscript
static func remaining(boss, exposed_until: float, now: float) -> float
```

### `amplify`

```gdscript
static func amplify(damage: float, boss, exposed_until: float, now: float) -> float
```

Only called in the server's infected branch, for the current raid boss.

