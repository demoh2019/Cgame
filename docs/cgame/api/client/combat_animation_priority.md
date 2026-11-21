# combat_animation_priority.gd

> Simulation-LOD-style visual priority.

`res://scripts/client/combat_animation_priority.gd`

## Overview

Simulation-LOD-style visual priority. Authoritative combat never slows down;
only the rate at which distant crowd skeletons are posed is adjusted.
The native controller has a hard per-frame budget, and stock Godot uses
the existing CharacterModel tier-1 full-rate (no costly foot IK) fallback.

## Constants

- `const SLOTS := [0, 1, 4, 8]`
- `const ZOMBIE_CHASE := 2`
- `const ZOMBIE_ATTACK := 3`

## Functions

### `slots`

```gdscript
static func slots(quality: int) -> int
```

### `wants_priority`

```gdscript
static func wants_priority(kind: String, entity: Dictionary) -> bool
```

