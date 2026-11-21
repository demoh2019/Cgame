# guild_alliances.gd

> Albion-style guild alliances.

`res://scripts/shared/guild_alliances.gd`

## Overview

Albion-style guild alliances. Guild leaders (verified Nakama rank 0) invite another
guild's leader at the hub; on acceptance both guilds share an alliance, and allied
members never hit or intercept each other's attacks in PvP. A leader can leave at
any time. Guild ids come only from the server-side identity check.

## Constants

- `const MAX_GUILDS := 4`
- `const INVITE_SECONDS := 120.0`
- `const LEADER_RANK := 0`

## Functions

### `is_leader`

```gdscript
static func is_leader(rank: int) -> bool
```

### `friendly`

```gdscript
static func friendly(guild_a: String, guild_b: String, guild_to_alliance: Dictionary) -> bool
```

True when two verified guild ids are the same guild or share an alliance.

