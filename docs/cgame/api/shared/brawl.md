# brawl.gd

> First-person brawling rules: every melee swing costs stamina, holding the attack charges a power blow that staggers and knocks down, a kick shoves and floors...

`res://scripts/shared/brawl.gd`

## Overview

First-person brawling rules: every melee swing costs stamina, holding the attack charges a
power blow that staggers and knocks down, a kick shoves and floors staggered enemies, a downed
enemy takes a brutal ground finisher, and Rage builds from trading blows. Pure functions;
the server owns all state and applies them.

## Constants

- `const LIGHT_STAMINA := 6.0`
- `const POWER_STAMINA := 22.0 # At full charge; scales with charge.`
- `const EXHAUSTED_DAMAGE := 0.7 # Swinging on an empty stamina bar: weak, slow blows.`
- `const EXHAUSTED_COOLDOWN := 1.7`
- `const POWER_DAMAGE := 1.3 # Extra damage at full charge (x2.3 total).`
- `const POWER_COOLDOWN := 0.5`
- `const POWER_STAGGER_CHARGE := 0.75 # Charge from which a power blow staggers/knocks down.`
- `const POWER_STAGGER_SECONDS := 1.2`
- `const POWER_KNOCKBACK := 1.3`
- `const KICK_STAMINA := 12.0`
- `const KICK_COOLDOWN := 0.9`
- `const KICK_RANGE := 2.3`
- `const KICK_DAMAGE := 5.0`
- `const KICK_KNOCKBACK := 1.7`
- `const KICK_STAGGER_SECONDS := 0.9`
- `const DOWN_SECONDS := 2.6 # A staggered enemy hit by a kick or power blow goes down this long.`
- `const GROUND_FINISHER := 2.5 # Damage multiplier on a downed enemy.`
- `const RAGE_MAX := 100.0`
- `const RAGE_PER_DAMAGE_DEALT := 0.45`
- `const RAGE_PER_DAMAGE_TAKEN := 1.1`
- `const RAGE_SECONDS := 12.0`
- `const RAGE_DAMAGE := 1.5`
- `const RAGE_TAKEN := 0.6`
- `const RAGE_COOLDOWN := 0.75`

## Functions

### `swing_cost`

```gdscript
static func swing_cost(charge: float) -> float
```

### `damage_factor`

```gdscript
static func damage_factor(charge: float, exhausted: bool, raging: bool) -> float
```

### `cooldown_factor`

```gdscript
static func cooldown_factor(charge: float, exhausted: bool, raging: bool) -> float
```

### `gain_rage`

```gdscript
static func gain_rage(rage: float, amount: float) -> float
```

