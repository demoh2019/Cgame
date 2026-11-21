# raid_round_robin.gd

> Optional fair-share raid loot on ONE server-owned boss bag.

`res://scripts/shared/raid_round_robin.gd`

## Overview

Optional fair-share raid loot on ONE server-owned boss bag.
The same bag's inventory is reduced on every accepted claim; no duplication.
Identity tokens and turns are never accepted from clients.

## Constants

- `const RaidLoot = preload("res://scripts/shared/raid_loot.gd")`
- `const TURN_SECONDS := 12.0`
- `const MAX_PARTICIPANTS := 5`

## Functions

### `activate`

```gdscript
static func activate(bag: Dictionary, identities: Array, boss_id: int, now: float) -> bool
```

### `active`

```gdscript
static func active(bag: Dictionary, now: float) -> bool
```

### `turn`

```gdscript
static func turn(bag: Dictionary, player, now: float) -> Dictionary
```

No state mutation when merely checking a turn (e.g. for snapshots).

### `offer`

```gdscript
static func offer(bag: Dictionary, player, now: float, requested_item: String = "") -> Dictionary
```

One claim gets one item type and at most 1/N of its ORIGINAL count.
This prevents a first-click grab of an entire currency stack.
Empty choice preserves Q auto-loot; explicit choices are validated against
the original server-owned bag before any inventory transfer.

### `choice_ids`

```gdscript
static func choice_ids(bag: Dictionary) -> Array[String]
```

Called only after inventory.add actually accepts positive items.
Only material item IDs, not identities or private loot rotation metadata,
may be sent to a contributor whose turn is active.

### `complete`

```gdscript
static func complete(bag: Dictionary, current_index: int, now: float) -> void
```

### `skip_turn`

```gdscript
static func skip_turn(bag: Dictionary, player, now: float) -> Dictionary
```

The actual turn holder may yield without claiming anything. This does not
mutate the bag inventory and cannot be requested for another identity.

### `visible`

```gdscript
static func visible(bag: Dictionary, player, now: float) -> Dictionary
```

