# training_duel.gd

> (no header comment)

`res://scripts/shared/training_duel.gd`

## Constants

- `const RaidLoot = preload("res://scripts/shared/raid_loot.gd")` - Nonlethal consent-only sparring. Never trust client-side duel permissions.
- `const INVITE_SECONDS := 20.0`
- `const INVITE_COOLDOWN := 8.0`
- `const MATCH_SECONDS := 120.0`
- `const MAX_INVITE_DISTANCE := 8.0`
- `const MAX_SEPARATION := 25.0`

## Functions

### `invitation_reason`

```gdscript
static func invitation_reason(world, first, second, now: float) -> String
```

### `active_for`

```gdscript
static func active_for(duels: Dictionary, world, attacker, victim, now: float) -> bool
```

