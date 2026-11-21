# outpost_breach.gd

> Siege breaching: attackers spend refined crafting materials to dismantle one tier of a rival party's outpost walls.

`res://scripts/shared/outpost_breach.gd`

## Overview

Siege breaching: attackers spend refined crafting materials to dismantle
one tier of a rival party's outpost walls. Executed only on world server.
No attacker-provided party IDs, prices, cooldowns or fortification levels.

## Constants

- `const ACCESS_RADIUS := 4.0`
- `const MIN_ATTACKERS := 2`
- `const BREACH_COOLDOWN := 45.0`
- `const COST := {"plank_2": 2, "bar_2": 2}`

## Functions

### `breach`

```gdscript
static func breach(site: Dictionary, inventory, attacker_group: int, attacker_position: Vector3, allies_present: int, now: float) -> Dictionary
```

