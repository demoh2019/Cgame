# melee_parry.gd

> A timed, one-hit front-facing block for regular infected melee.

`res://scripts/shared/melee_parry.gd`

## Overview

A timed, one-hit front-facing block for regular infected melee.
No effect on other survivors, ranged hazards or boss area attacks.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const STAMINA_COST := 20.0`
- `const WINDOW_SECONDS := 0.45`
- `const COOLDOWN_SECONDS := 4.0`
- `const ATTACK_LOCK := 0.35`
- `const DAMAGE_FACTOR := 0.30`
- `const WOUND_FACTOR := 0.30`
- `const STAGGER_SECONDS := 1.0`
- `const MAX_DISTANCE := 2.7`
- `const FRONT_DOT := 0.35`

## Functions

### `equipped`

```gdscript
static func equipped(inventory) -> bool
```

### `can_block`

```gdscript
static func can_block(defender, infected) -> bool
```

Both orientation and equipment are checked on the server AT IMPACT.
Only a real front-facing attack can consume an active parry window.

