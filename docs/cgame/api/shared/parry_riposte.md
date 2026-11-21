# parry_riposte.gd

> A short PvE-only follow-up for a server-confirmed frontal melee parry.

`res://scripts/shared/parry_riposte.gd`

## Overview

A short PvE-only follow-up for a server-confirmed frontal melee parry.
The impact target and weapon are session-only; clients cannot fabricate them.

## Constants

- `const MeleeParry = preload("res://scripts/shared/melee_parry.gd")`
- `const WINDOW_SECONDS := 2.25`
- `const DAMAGE_FACTOR := 1.40`

## Functions

### `clear`

```gdscript
static func clear(player) -> void
```

### `arm`

```gdscript
static func arm(player, infected) -> bool
```

Called only at the actual server-owned impact, never at F8 activation.

### `can_strike`

```gdscript
static func can_strike(player, infected, weapon: String) -> bool
```

Normal hit resolution and reach are enforced by GameServer._find_hit.

### `tick`

```gdscript
static func tick(player, delta: float) -> void
```

