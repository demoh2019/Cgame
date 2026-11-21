# sunder_mark.gd

> Bounded nonstacking PvE vulnerability derived from server-authored hits.

`res://scripts/shared/sunder_mark.gd`

## Overview

Bounded nonstacking PvE vulnerability derived from server-authored hits.
Expiration uses world time, not client input or far-away zombie AI ticks.

## Constants

- `const DURATION := 4.5`
- `const NORMAL_BONUS := 0.18`
- `const ELITE_BONUS := 0.10`
- `const RAID_BOSS_BONUS := 0.06`

## Functions

### `remaining`

```gdscript
static func remaining(infected, now: float) -> float
```

### `multiplier`

```gdscript
static func multiplier(infected, now: float) -> float
```

### `amplify`

```gdscript
static func amplify(damage: float, infected, now: float) -> float
```

