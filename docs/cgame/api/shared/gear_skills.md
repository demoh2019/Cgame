# gear_skills.gd

> Albion Online-style gear-defined ability bar.

`res://scripts/shared/gear_skills.gd`

## Overview

```text
Albion Online-style gear-defined ability bar. Your build IS your class:
  Q  - the weapon's skill (Combat.active_skill, existing G key)
  E  - the weapon's ultimate: a charged version of Q, long cooldown
  R  - chest armor: Iron Skin (damage reduction for a few seconds)
  D  - helmet: Second Wind (heal over time)
  F  - boots: Sprint (movement speed burst)
Strength scales with item power (tier + enchant). Cooldowns are per slot and
everything is validated on the server; the client only sends the slot.
```

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const SLOTS := ["armor", "head", "feet"]`
- `const ULTIMATE_DAMAGE := 2.2`
- `const ULTIMATE_COOLDOWN := 3.0`
- `const ULTIMATE_ENERGY := 1.6`
- `const MAX_GUARD := 0.5`
- `const MAX_SPEED := 0.4`

## Functions

### `power_scale`

```gdscript
static func power_scale(item_id: String) -> float
```

Item-power scale: 1.0 at T1 flat (400 IP), +12.5% per 100 IP.

### `skill_for`

```gdscript
static func skill_for(slot: String, item_id: String) -> Dictionary
```

The armor-slot skill granted by an equipped item, or {} when the slot is empty/unknown.

### `ultimate`

```gdscript
static func ultimate(skill: Dictionary) -> Dictionary
```

The weapon's ultimate (E): Q's skill charged up.

### `equipped_in`

```gdscript
static func equipped_in(inventory, slot: String) -> String
```

Item equipped in an armor-type slot of an inventory.

