# pvp_honor.gd

> PvP glory independent from persistent PvE renown and criminal infamy.

`res://scripts/shared/pvp_honor.gd`

## Overview

PvP glory independent from persistent PvE renown and criminal infamy.
Only real server-confirmed PvP deaths add kills; repeated victims earn
honor at most once per five minutes per stable account or guest identity.

## Constants

- `const RaidLoot = preload("res://scripts/shared/raid_loot.gd")`
- `const MAX_POINTS := 100000`
- `const RED_REWARD := 4`
- `const BLACK_REWARD := 10`
- `const SAME_VICTIM_SECONDS := 300.0`
- `const MAX_VICTIMS := 24`
- `const MAX_ATTACKERS := 1024`

## Functions

### `rank`

```gdscript
static func rank(points: int) -> String
```

### `record`

```gdscript
static func record(attacker, victim, zone: int, now: float, ledger: Dictionary) -> Dictionary
```

The ledger is session-scoped and never client-provided or persisted.

