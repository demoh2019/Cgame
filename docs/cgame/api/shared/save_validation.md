# save_validation.gd

> Shared, strict, side-effect-free validation of persistent character containers.

`res://scripts/shared/save_validation.gd`

## Overview

Shared, strict, side-effect-free validation of persistent character containers.
Treat Nakama storage as persisted input, not an implicit authority to mint items.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const Inventory = preload("res://scripts/shared/inventory.gd")`
- `const MAX_COUNTER := 2147483647`

## Functions

### `finite_number`

```gdscript
static func finite_number(value: Variant, lower: float, upper: float) -> bool
```

### `valid_counter`

```gdscript
static func valid_counter(value: Variant) -> bool
```

### `parse_inventory`

```gdscript
static func parse_inventory(raw: Variant, expected_slots: int, allow_equipment: bool = true) -> Dictionary
```

Returns {"inventory": Inventory} or {}, never partial data.
allow_equipment=false is used for settlement bank stacks (not wearable slots).

### `whole_numbers_as_ints`

```gdscript
static func whole_numbers_as_ints(value: Variant) -> Variant
```

JSON has one number type, so every whole number comes back as a float (3 -> 3.0). The game's save validators are strict
about integer fields (tests pin that a tier of 2.0 handed to a validator is refused), and storage cannot tell 2 from 2.0,
so a document read from storage (Nakama or the offline solo file) gets its whole numbers turned back into integers once,
before any validator sees it. Fractions stay floats.

