# stealth_ambush.gd

> (no header comment)

`res://scripts/shared/stealth_ambush.gd`

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")` - A one-off PvE rear strike: only legitimate server-owned melee encounters.
- `const Zombie = preload("res://scripts/shared/zombie.gd")`
- `const DAMAGE_MULTIPLIER := 1.45`
- `const MAX_DISTANCE := 2.4`
- `const MAX_REAR_DOT := -0.55`

## Functions

### `multiplier`

```gdscript
static func multiplier(attacker, infected, weapon_id: String) -> float
```

