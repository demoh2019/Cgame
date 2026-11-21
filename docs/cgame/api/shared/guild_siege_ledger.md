# guild_siege_ledger.gd

> (no header comment)

`res://scripts/shared/guild_siege_ledger.gd`

## Constants

- `const GuildTerritory = preload("res://scripts/shared/guild_territory.gd")` - Pure validation of server-generated siege victories before writing a permanent Nakama guild score. Never trust an ENet-supplied victory or tag.

## Functions

### `eligible_victory`

```gdscript
static func eligible_victory(event: Variant, sim) -> Dictionary
```

