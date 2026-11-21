# inventory.gd

> A fixed number of slots holding stacks of items, plus one slot each for the weapon, armour and tool in use.

`res://scripts/shared/inventory.gd`

## Overview

A fixed number of slots holding stacks of items, plus one slot each for the weapon, armour and
tool in use. Pure data: no scene, so the server owns it and the client gets copies.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const TrailBackpack = preload("res://scripts/shared/trail_backpack.gd")`
- `const GearDurability = preload("res://scripts/shared/gear_durability.gd")`
- `const GEAR_SLOTS := ["head", "cape", "hands", "feet"]`

## Functions

### `count`

```gdscript
func count(id: String) -> int
```

### `total_weight`

```gdscript
func total_weight() -> float
```

Equipped gear remains physically in its backpack slot, so it is counted only once.

### `movement_factor`

```gdscript
func movement_factor(capacity_bonus: float = 0.0) -> float
```

Only physically owned foot support and trained capacity adjust load comfort.

### `has_all`

```gdscript
func has_all(inputs: Dictionary) -> bool
```

### `free_space_for`

```gdscript
func free_space_for(id: String) -> int
```

### `add`

```gdscript
func add(id: String, amount: int) -> int
```

Adds as many as fit and returns the number that did not.

### `remove`

```gdscript
func remove(id: String, amount: int) -> bool
```

Removes exactly `amount` or nothing. Returns whether it succeeded.

### `equip`

```gdscript
func equip(id: String) -> bool
```

### `worn`

```gdscript
func worn() -> Array
```

Everything worn for protection: the body armor and the pieces in the gear slots.

### `is_equipped`

```gdscript
func is_equipped(id: String) -> bool
```

### `unequip_missing`

```gdscript
func unequip_missing() -> void
```

### `best_tool`

```gdscript
func best_tool(tool_kind: String) -> String
```

Best tool of a kind that is carried (the highest tier).

### `take_everything`

```gdscript
func take_everything() -> Dictionary
```

Empties the inventory (including equipment) and returns everything as {id: count}.

### `to_dict`

```gdscript
func to_dict() -> Dictionary
```

### `load_dict`

```gdscript
func load_dict(data: Dictionary) -> void
```

### `durability`

```gdscript
func durability(id: String) -> float
```

Durability of an item (100 when never damaged).

### `effectiveness`

```gdscript
func effectiveness(id: String) -> float
```

1.0 normally, 0.5 for broken (0%) gear.

### `damage_item`

```gdscript
func damage_item(id: String, amount: float) -> void
```

### `wear_worn`

```gdscript
func wear_worn(amount: float = GearDurability.ARMOR_WEAR_PER_HIT) -> void
```

Wear on everything worn for protection (one received hit).

### `wear_equipped`

```gdscript
func wear_equipped(amount: float) -> void
```

Wear on every equipped item (weapon and protection), e.g. on a kept-gear death.

### `repair_cost`

```gdscript
func repair_cost() -> int
```

Silver needed to repair every damaged carried item.

### `repair_all`

```gdscript
func repair_all() -> Array
```

Restores every carried damaged item to 100%. Returns the item ids repaired.

_1 private function(s) starting with `_` are not listed._
