# party_flank.gd

> (no header comment)

`res://scripts/shared/party_flank.gd`

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")` - Coordinated PvE flanking for existing party tanks + melee damage dealers. The infected must be fighting a DIFFERENT, close, living party member. No client commands, attacker-chosen targets, persistence or PvP effects.
- `const Zombie = preload("res://scripts/shared/zombie.gd")`
- `const MAX_MELEE_DISTANCE := 3.2`
- `const MAX_TANK_DISTANCE := 10.0`
- `const MAX_HEIGHT := 3.0`
- `const REAR_DOT := -0.55`
- `const DAMAGE_BONUS := 0.18`
- `const BOSS_DAMAGE_BONUS := 0.10`

## Functions

### `qualifies`

```gdscript
static func qualifies(attacker, infected, players: Dictionary, parties, world) -> bool
```

### `damage`

```gdscript
static func damage(base_damage: float, boss: bool) -> float
```

