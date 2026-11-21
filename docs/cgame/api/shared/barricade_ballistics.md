# barricade_ballistics.gd

> PvP siege gunfire damages only real server-created barricades.

`res://scripts/shared/barricade_ballistics.gd`

## Overview

PvP siege gunfire damages only real server-created barricades.
Existing wall tiers, HP, rebuilding and obstacle removal remain authoritative.

## Constants

- `const Structures = preload("res://scripts/shared/structures.gd")`
- `const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")`
- `const DAMAGE_FRACTION := 0.6`
- `const MAX_RAW_DAMAGE := 48.0`

## Functions

### `can_damage`

```gdscript
static func can_damage(attacker, wall: Dictionary, attacker_zone: int, wall_zone: int) -> bool
```

### `raw_damage`

```gdscript
static func raw_damage(verified_weapon_damage: float) -> float
```

Convert verified equipped-weapon damage into structure damage.
The usual tier resistance is applied separately by damage_barricade().

