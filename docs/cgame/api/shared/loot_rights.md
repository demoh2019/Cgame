# loot_rights.gd

> Short-lived, server-owned PvE loot reservations.

`res://scripts/shared/loot_rights.gd`

## Overview

Short-lived, server-owned PvE loot reservations. Player full-loot bags are public.

## Constants

- `const RaidLoot = preload("res://scripts/shared/raid_loot.gd")`
- `const RESERVATION_SECONDS := 18.0`

## Functions

### `reservation`

```gdscript
static func reservation(participants: Array, now: float) -> Dictionary
```

Freeze actual Player identities at the moment of the kill.
Accounts survive reconnect; guests are tied to one RefCounted session instance,
so a reused network peer number cannot steal loot from a disconnected survivor.

### `reserved`

```gdscript
static func reserved(bag: Dictionary, now: float) -> bool
```

### `can_loot`

```gdscript
static func can_loot(bag: Dictionary, player, now: float) -> bool
```

### `visible_state`

```gdscript
static func visible_state(bag: Dictionary, player, now: float) -> Dictionary
```

Only viewer-specific flags travel over the network, never identities.

