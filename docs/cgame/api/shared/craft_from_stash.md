# craft_from_stash.gd

> Transactional hub-only crafting from carried + banked materials.

`res://scripts/shared/craft_from_stash.gd`

## Overview

Transactional hub-only crafting from carried + banked materials.
The authoritative server checks hub location, level, life and mount state.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const Inventory = preload("res://scripts/shared/inventory.gd")`
- `const Crafting = preload("res://scripts/shared/crafting.gd")`
- `const MAX_BATCHES := 50`

## Functions

### `craft`

```gdscript
static func craft(carried, protected_bank, recipe_id: String, times: int = 1) -> int
```

Prefer consuming carried ingredients, then banked units. All changes are
staged in clones until the output has room in the backpack; rollback is
exact even when the recipe consumes equipped materials or stack slots.

