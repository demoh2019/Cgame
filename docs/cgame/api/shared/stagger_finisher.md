# stagger_finisher.gd

> (no header comment)

`res://scripts/shared/stagger_finisher.gd`

## Constants

- `const MeleeParry = preload("res://scripts/shared/melee_parry.gd")` - PvE finisher: server-only target selection after a real infected stun. No player ID is sent over the wire and no PvP or raid-boss damage is possible.
- `const Combat = preload("res://scripts/shared/combat.gd")`
- `const RangedCover = preload("res://scripts/shared/ranged_cover.gd")`
- `const ENERGY_COST := 24.0`
- `const COOLDOWN_SECONDS := 6.0`
- `const ATTACK_LOCK := 0.65`
- `const RECOVERY_SECONDS := 0.45`
- `const DAMAGE_MULTIPLIER := 1.7`
- `const MAX_REACH := 3.9`
- `const FRONT_DOT := 0.30`

## Functions

### `eligible`

```gdscript
static func eligible(world, survivor, infected) -> bool
```

### `nearest`

```gdscript
static func nearest(world, survivor, zombies: Dictionary)
```

### `damage`

```gdscript
static func damage(weapon_id: String, progression, skills) -> float
```

