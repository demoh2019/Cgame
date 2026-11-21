# outpost_supplies.gd

> Finite, contested PvP outpost supply caches.

`res://scripts/shared/outpost_supplies.gd`

## Overview

Finite, contested PvP outpost supply caches. Accounts cannot duplicate
supplies with repeated RPCs, reconnects or an intentionally full backpack.
Claims and stock live on the server session, not inside client snapshots.

## Constants

- `const Inventory = preload("res://scripts/shared/inventory.gd")`
- `const RaidLoot = preload("res://scripts/shared/raid_loot.gd")`
- `const CACHE_STOCK := 5`
- `const ACCESS_RANGE := 4.0`

## Functions

### `initialize_capture`

```gdscript
static func initialize_capture(site: Dictionary) -> void
```

### `reward`

```gdscript
static func reward(zone: int) -> Dictionary
```

### `claim`

```gdscript
static func claim(site: Dictionary, player, group_id: int, zone: int, now: float, contested: bool) -> Dictionary
```

