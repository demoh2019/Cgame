# guardian_intercept.gd

> (no header comment)

`res://scripts/shared/guardian_intercept.gd`

## Constants

- `const GuardianTaunt = preload("res://scripts/shared/guardian_taunt.gd")` - PvE guardian intercept: block one infected MELEE blow for one party ally. Enemy attack, the protected target and actual damage remain server-owned.
- `const RANGE := 4.5`
- `const MAX_HEIGHT := 3.0`
- `const DURATION := 9.0`
- `const COOLDOWN := 28.0`
- `const ENERGY_COST := 20.0`
- `const REDIRECT_FRACTION := 0.65`

## Functions

### `can_guard`

```gdscript
static func can_guard(guardian, ally, parties, world) -> bool
```

### `can_intercept`

```gdscript
static func can_intercept(guardian, ally, parties, world) -> bool
```

### `damage`

```gdscript
static func damage(raw_damage: float) -> float
```

