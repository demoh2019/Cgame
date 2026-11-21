# raid_need_greed.gd

> Optional Need / Greed / Pass for the infected core of ONE raid boss bag.

`res://scripts/shared/raid_need_greed.gd`

## Overview

Optional Need / Greed / Pass for the infected core of ONE raid boss bag.
This script never creates items: winners only gain permission to claim the
original trophy stack in the normal server inventory transaction.

## Constants

- `const RaidLoot = preload("res://scripts/shared/raid_loot.gd")`
- `const ITEM_ID := "infected_core"`
- `const VOTE_SECONDS := 25.0`
- `const MAX_VOTERS := 5`
- `const CHOICES := ["need", "greed", "pass"]`

## Functions

### `activate`

```gdscript
static func activate(bag: Dictionary, identities: Array, boss_id: int, now: float) -> bool
```

Freeze tokens at death. Existing bag loot and existing reservations remain.

### `resolve`

```gdscript
static func resolve(bag: Dictionary, now: float) -> Dictionary
```

Lazy, idempotent resolution lets voting finish without a new server ticker.

### `vote`

```gdscript
static func vote(bag: Dictionary, player, choice: String, now: float) -> Dictionary
```

A remote client sends only a choice and a bag ID. The server supplies
the real authenticated Player, time, bag and frozen entitlement list.

### `protection`

```gdscript
static func protection(bag: Dictionary, player, now: float) -> Dictionary
```

Protect the original trophy only until the existing raid lock expires.
Other items in the same physical bag can be looted normally.

### `visible`

```gdscript
static func visible(bag: Dictionary, player, now: float) -> Dictionary
```

Only viewer-specific vote status: no account/session tokens, rolls of
opponents, or private ballots are serialized to the network.

_1 private function(s) starting with `_` are not listed._
