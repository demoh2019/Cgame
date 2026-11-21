# party_corpse_rescue.gd

> (no header comment)

`res://scripts/shared/party_corpse_rescue.gd`

## Constants

- `const DeathRecovery = preload("res://scripts/shared/death_recovery.gd")` - Explicit team call for a real *public* death bag, not an extra loot right. The owner, bag, group and expiration are all server-authenticated.
- `const RaidLoot = preload("res://scripts/shared/raid_loot.gd")`
- `const SECONDS := 90.0`
- `const COOLDOWN := 18.0`

## Functions

### `request`

```gdscript
static func request(player, parties, bags: Dictionary, now: float) -> Dictionary
```

### `shared`

```gdscript
static func shared(peer_id: int, players: Dictionary, parties, bags: Dictionary, now: float) -> Dictionary
```

Generate the preview for each actual current group member separately.
When the author leaves or a bag is stolen, the marker vanishes at once.

