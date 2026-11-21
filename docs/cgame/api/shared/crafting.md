# crafting.gd

> Crafting rules: what a recipe needs, whether the player is at a station, and the transaction itself (inputs removed and output added, or nothing changes).

`res://scripts/shared/crafting.gd`

## Overview

Crafting rules: what a recipe needs, whether the player is at a station, and the transaction
itself (inputs removed and output added, or nothing changes).

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `enum Result { OK, UNKNOWN_RECIPE, MISSING_INPUTS, NO_STATION, NO_SPACE }`

## Functions

### `can_craft`

```gdscript
static func can_craft(inventory, recipe_id: String, at_workbench: bool, at_campfire: bool = false) -> int
```

### `craft`

```gdscript
static func craft(inventory, recipe_id: String, at_workbench: bool, times: int = 1, at_campfire: bool = false) -> int
```

Crafts `times` batches. Returns a Result. Atomic: either everything happens or nothing does.

### `craftable`

```gdscript
static func craftable(inventory) -> Array
```

Recipes the inventory could craft right now (ignoring stations), for the UI.

