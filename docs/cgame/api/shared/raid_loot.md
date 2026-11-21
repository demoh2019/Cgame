# raid_loot.gd

> Temporary access control for ONE shared raid boss reward bag.

`res://scripts/shared/raid_loot.gd`

## Overview

Temporary access control for ONE shared raid boss reward bag.
World loot remains a single inventory; this never duplicates boss prizes.
Entitlement identities are server-only, not public replicated player IDs.

## Constants

- `const Party = preload("res://scripts/shared/party.gd")`
- `const LOCK_SECONDS := 75.0`

## Functions

### `token`

```gdscript
static func token(player) -> String
```

### `eligible`

```gdscript
static func eligible(killer, boss, players: Dictionary, parties, world, now: float) -> Array
```

Victory is awarded to the real killing player and same-party survivors
who contributed a valid equipped-weapon hit in the last assist window.
No distant spectators, AFK members, cross-zone participants or late joins.

### `reserve`

```gdscript
static func reserve(bag: Dictionary, identities: Array, now: float) -> void
```

### `remaining`

```gdscript
static func remaining(bag: Dictionary, now: float) -> float
```

### `can_open`

```gdscript
static func can_open(bag: Dictionary, player, now: float) -> bool
```

