# gear_salvage.gd

> Server-owned, atomic recycling of unequipped gear into crafting materials.

`res://scripts/shared/gear_salvage.gd`

## Overview

Server-owned, atomic recycling of unequipped gear into crafting materials.
Every yield is calculated from the current item database, never client input.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const Inventory = preload("res://scripts/shared/inventory.gd")`

## Functions

### `materials_for`

```gdscript
static func materials_for(item_id: String) -> Dictionary
```

### `transact`

```gdscript
static func transact(inventory: Inventory, item_id: String) -> Dictionary
```

