# guardian_retribution.gd

> PvE Guardian Retribution: a real intercepted infected melee strike briefly lets the guardian challenge its source and punish that SAME living enemy.

`res://scripts/shared/guardian_retribution.gd`

## Overview

PvE Guardian Retribution: a real intercepted infected melee strike briefly
lets the guardian challenge its source and punish that SAME living enemy.
Client requests cannot arm or select a retaliation target.

## Constants

- `const GuardianTaunt = preload("res://scripts/shared/guardian_taunt.gd")`
- `const COUNTER_SECONDS := 4.0`
- `const TAUNT_SECONDS := 1.5`
- `const DAMAGE_MULTIPLIER := 1.25`

## Functions

### `clear`

```gdscript
static func clear(guardian) -> void
```

### `arm`

```gdscript
static func arm(guardian, infected, parties, world) -> bool
```

Arm only in the authoritative, already-confirmed melee interception path.

### `consume`

```gdscript
static func consume(guardian, infected, parties, world) -> bool
```

First server-accepted normal melee swing consumes the window, EVEN on a
miss or another target. No ranged attacks, PvP or fake equipment can
spend the buff as a successful counterstrike. Expiration is tick-driven.

### `amplify`

```gdscript
static func amplify(damage: float) -> float
```

