# guardian_taunt.gd

> Classless party guardian: server-owned redirection of infected already pursuing allies.

`res://scripts/shared/guardian_taunt.gd`

## Overview

Classless party guardian: server-owned redirection of infected already
pursuing allies. Client cannot choose a zombie or manipulate its hate.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const RADIUS := 12.0`
- `const MAX_TARGETS := 3`
- `const FOCUS_SECONDS := 3.0`
- `const COOLDOWN := 20.0`
- `const ENERGY_COST := 25.0`
- `const GUARD_SECONDS := FOCUS_SECONDS`
- `const INFECTED_DAMAGE_REDUCTION := 0.30`

## Functions

### `brace_damage`

```gdscript
static func brace_damage(damage: float, seconds: float, equipped: bool, grouped: bool) -> float
```

Apply after armor only to an active, melee-equipped group guardian.
No infection, bleed, poison, hunger or player-vs-player reduction.

### `melee_equipped`

```gdscript
static func melee_equipped(inventory) -> bool
```

### `eligible_enemy`

```gdscript
static func eligible_enemy(enemy, origin: Vector3, members: Array, world) -> bool
```

