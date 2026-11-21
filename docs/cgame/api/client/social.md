# social.gd

> Chat and guilds, entirely from Nakama: a world chat room, a guild chat, and Nakama groups as guilds.

`res://scripts/client/social.gd`

## Overview

Chat and guilds, entirely from Nakama: a world chat room, a guild chat, and Nakama groups as guilds.
The same node serves the HUD and the tests.

## Constants

- `const NakamaScript = preload("res://addons/com.heroiclabs.nakama/Nakama.gd")`
- `const CHANNEL_ROOM := 1`
- `const CHANNEL_GROUP := 3`
- `const MAX_MESSAGE_LENGTH := 200`

## Signals

- `signal message_received(channel: String, sender: String, text: String)`
- `signal guild_changed`

## Functions

### `sign_in`

```gdscript
func sign_in(host: String, port: int, device_id: String, username: String) -> Dictionary
```

Signs in with a device id (kept in user://) so the same machine is the same account.

### `start_chat`

```gdscript
func start_chat(room_name: String = "world") -> bool
```

### `clean`

```gdscript
static func clean(text: String) -> String
```

### `say`

```gdscript
func say(text: String) -> bool
```

### `say_guild`

```gdscript
func say_guild(text: String) -> bool
```

### `refresh_guild`

```gdscript
func refresh_guild() -> void
```

### `create_guild`

```gdscript
func create_guild(guild_name: String) -> Dictionary
```

### `list_guilds`

```gdscript
func list_guilds(prefix: String = "") -> Array
```

### `join_guild`

```gdscript
func join_guild(group_id: String) -> Dictionary
```

### `leave_guild`

```gdscript
func leave_guild() -> bool
```

### `guild_members`

```gdscript
func guild_members() -> Array
```

### `list_friends`

```gdscript
func list_friends() -> Array
```

Friends, from Nakama: [{"name", "online", "state"}], where state 0 = friends, 1 = you invited them, 2 = they invited
you, 3 = blocked.

### `add_friend`

```gdscript
func add_friend(username: String) -> Dictionary
```

Sends a friend request (or accepts theirs) by player name.

### `shutdown`

```gdscript
func shutdown() -> void
```

_3 private function(s) starting with `_` are not listed._
