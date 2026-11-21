# infected_melee_cover.gd

> Prevent an infected's ordinary melee strike from passing through solid cover.

`res://scripts/shared/infected_melee_cover.gd`

## Overview

Prevent an infected's ordinary melee strike from passing through solid cover.
Reuse the same authoritative blocker geometry as first-contact sight and
projectile collision; special raid-boss swings retain encounter semantics.

## Constants

- `const InfectedSight = preload("res://scripts/shared/infected_sight.gd")`

## Functions

### `clear_attack`

```gdscript
static func clear_attack(world, origin: Vector3, target: Vector3, raid_boss: bool = false) -> bool
```

