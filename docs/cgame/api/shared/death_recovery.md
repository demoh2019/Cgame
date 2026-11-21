# death_recovery.gd

> (no header comment)

`res://scripts/shared/death_recovery.gd`

## Constants

- `const RaidLoot = preload("res://scripts/shared/raid_loot.gd")` - Tracks only the current survivor's own full-loot death bag. The world bag stays public and lootable by everyone: this provides a private route, not protection, restoration of contents or a second copy of the items.
- `const WorldGen = preload("res://scripts/shared/world_gen.gd")`
- `const TravelNavigation = preload("res://scripts/shared/travel_navigation.gd")`

## Functions

### `tag`

```gdscript
static func tag(bag: Dictionary, player) -> void
```

Called only during the real server-authoritative full-loot death path.
The token identifies an authenticated account across same-server reconnects,
or an original RefCounted guest session (not its recyclable peer number).

### `public_mark`

```gdscript
static func public_mark(bags: Dictionary, player, now: float) -> Dictionary
```

Newest *surviving* owner bag is the navigable destination. The marker has no
ID, item list, owner token, guild information or loot permissions. It cannot
outlive its real public bag, including when other players loot everything.

