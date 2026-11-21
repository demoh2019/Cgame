# crafting_catalog.gd

> Search/filter and safe bulk-batch previews for the crafting UI.

`res://scripts/shared/crafting_catalog.gd`

## Overview

Search/filter and safe bulk-batch previews for the crafting UI.
Pure local estimates: GameServer.cmd_craft remains the sole authority.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const Crafting = preload("res://scripts/shared/crafting.gd")`
- `const CraftFromStash = preload("res://scripts/shared/craft_from_stash.gd")`
- `const Inventory = preload("res://scripts/shared/inventory.gd")`
- `const MAX_BATCHES := 50`

## Functions

### `matches`

```gdscript
static func matches(recipe_id: String, search: String) -> bool
```

### `max_batches`

```gdscript
static func max_batches(inventory, recipe_id: String, bank = null) -> int
```

Calculate a real transaction-safe maximum, including input stacks and
output room AFTER consuming materials. Descending scan is deliberate:
crafting 2 batches can free an input slot where crafting 1 cannot.

### `entries`

```gdscript
static func entries(inventory, search: String, ready_only: bool, crafting_level: int, bank = null) -> Array[Dictionary]
```

"Available" means inventory and crafting tier permit the recipe.
Station proximity, life, mount status and combat remain server-owned.

