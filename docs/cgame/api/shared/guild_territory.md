# guild_territory.gd

> Verified Nakama guild identity attached to session-based outpost ownership.

`res://scripts/shared/guild_territory.gd`

## Overview

Verified Nakama guild identity attached to session-based outpost ownership.
A banner is *derived* from live server-owned party membership on each read.
It is never persisted, and a client cannot submit a banner or guild name.

## Constants

- `const MIN_VERIFIED_MEMBERS := 2`

## Functions

### `party_banner`

```gdscript
static func party_banner(group_id: int, players: Dictionary, parties) -> Dictionary
```

### `owner_banner`

```gdscript
static func owner_banner(site: Dictionary, players: Dictionary, parties) -> Dictionary
```

### `same_owner_guild`

```gdscript
static func same_owner_guild(site: Dictionary, player, players: Dictionary, parties) -> bool
```

### `occupancy_side`

```gdscript
static func occupancy_side(site: Dictionary, player, players: Dictionary, parties) -> int
```

A verified guildmate defending the flag belongs to the same presence side
as the owning party. Unverified parties/guests retain old PvP rules.

