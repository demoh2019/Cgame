# stash_bulk.gd

> One atomic bulk deposit of carried raw/refined materials into private bank.

`res://scripts/shared/stash_bulk.gd`

## Overview

One atomic bulk deposit of carried raw/refined materials into private bank.
Existing inventory stacks/slots are the only source of truth.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const Inventory = preload("res://scripts/shared/inventory.gd")`

## Functions

### `eligible`

```gdscript
static func eligible(item_id: String) -> bool
```

### `deposit`

```gdscript
static func deposit(carried, protected_bank) -> Dictionary
```

Deterministic partial fill: IDs sorted lexicographically, up to actual
destination capacity. Stage both containers; neither mutates on failure.
This never touches food, water, medicine, equipment, tools or silver.

