# field_whetstone.gd

> Paid, limited melee preparation.

`res://scripts/shared/field_whetstone.gd`

## Overview

Paid, limited melee preparation. Pure rules used by the server and save loader.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const ITEM_ID := "field_whetstone"`
- `const HITS := 3`
- `const DAMAGE_FACTOR := 1.15`

## Functions

### `melee_weapon`

```gdscript
static func melee_weapon(inventory) -> String
```

### `valid_state`

```gdscript
static func valid_state(weapon: Variant, hits: Variant, inventory) -> bool
```

Strictly reject invalid persisted charges and equipment ownership.

### `bonus_active`

```gdscript
static func bonus_active(weapon: String, hits: int, inventory, attack_weapon: String) -> bool
```

