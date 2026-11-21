# arcane_abilities.gd

> Classless spells every survivor can cast, independent of the equipped weapon.

`res://scripts/shared/arcane_abilities.gd`

## Overview

Classless spells every survivor can cast, independent of the equipped weapon.
Arcane Bolt: a cheap, fast magic projectile (ranged, no ammo, costs combat energy).
Cataclysm: long-cooldown PvE blast against up to ULTIMATE_MAX_TARGETS
nearest infected inside the radius (never hits other survivors).
The server owns every number here; clients only send an aim direction.

## Constants

- `const BOLT_ENERGY_COST := 18.0`
- `const BOLT_COOLDOWN := 1.1`
- `const BOLT_ATTACK_LOCK := 0.35`
- `const BOLT_RANGE := 24.0`
- `const BOLT_BASE_DAMAGE := 16.0`
- `const ULTIMATE_ENERGY_COST := 60.0`
- `const ULTIMATE_COOLDOWN := 45.0`
- `const ULTIMATE_ATTACK_LOCK := 1.0`
- `const ULTIMATE_RADIUS := 7.0`
- `const ULTIMATE_BASE_DAMAGE := 70.0`
- `const ULTIMATE_MAX_TARGETS := 12`
- `const ULTIMATE_STAGGER_SECONDS := 1.2`

## Functions

### `bolt_damage`

```gdscript
static func bolt_damage(ranged_bonus: float) -> float
```

Bolt damage grows with the survivor's ranged training, like other ranged attacks.

### `ultimate_damage`

```gdscript
static func ultimate_damage(distance: float, melee_bonus: float) -> float
```

Full damage at the centre falling to half at the edge of the blast.

### `refusal`

```gdscript
static func refusal(alive: bool, mounted: bool, locked: bool, cooldown: float, energy: float, cost: float) -> String
```

Shared cast checks. Returns "" when the cast may start, otherwise the refusal reason.

