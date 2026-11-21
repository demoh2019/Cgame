# ability_bar.gd

> Albion-style ability bar: what your gear lets you do, with live cooldowns.

`res://scripts/client/ability_bar.gd`

## Overview

Albion-style ability bar: what your gear lets you do, with live cooldowns.
Slots: weapon skill (G), weapon ultimate (Alt+G), chest (Alt+H), helmet (Alt+J),
boots (Alt+K). Buttons are clickable; the server validates every use.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const Combat = preload("res://scripts/shared/combat.gd")`
- `const GearSkills = preload("res://scripts/shared/gear_skills.gd")`
- `const AbilityCooldowns = preload("res://scripts/client/ability_cooldowns.gd")`
- `const SLOT_DEFS := [`

## Functions

### `slot_label`

```gdscript
static func slot_label(slot: String, inventory, you: Dictionary, cooldown_override: float = -1.0) -> String
```

Text for one slot: ability name + cooldown, or the empty-slot hint.

_3 private function(s) starting with `_` are not listed._
