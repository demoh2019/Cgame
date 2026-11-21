# warden_aura.gd

> (no header comment)

`res://scripts/shared/warden_aura.gd`

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")` - Set synergy: a fully equipped relic warden shares limited PvE-only wound protection with nearby living party allies. All checks run on the server. No player commands, client-owned buff flags, stacking or PvP modifiers.
- `const RADIUS := 8.0`
- `const HEIGHT_LIMIT := 2.5`
- `const WOUND_REDUCTION := 0.15`
- `const WEAPON_ID := "purifier_maul_3"`
- `const ARMOR_ID := "warden_jacket_3"`

## Functions

### `carries_set`

```gdscript
static func carries_set(player) -> bool
```

### `active_for`

```gdscript
static func active_for(recipient, players: Dictionary, parties, world) -> bool
```

### `mitigate_wound`

```gdscript
static func mitigate_wound(amount: float, active: bool) -> float
```

