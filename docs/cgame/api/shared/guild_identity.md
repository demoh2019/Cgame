# guild_identity.gd

> (no header comment)

`res://scripts/shared/guild_identity.gd`

## Constants

- `const MAX_NAME := 24` - Identity returned by server-key-only Nakama RPC. Never accept a guild ID originating in an ENet client command or in a saved character document.
- `const MAX_ROLE := 2`
- `const UUID_PATTERN := "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"`

## Functions

### `normalize`

```gdscript
static func normalize(info: Variant) -> Dictionary
```

### `same_guild`

```gdscript
static func same_guild(first, second) -> bool
```

