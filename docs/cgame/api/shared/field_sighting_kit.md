# field_sighting_kit.gd

> (no header comment)

`res://scripts/shared/field_sighting_kit.gd`

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")` - Limited equipment-bound ranged damage preparation for server-verified infected.
- `const ITEM_ID := "field_sighting_kit"`
- `const HITS := 4`
- `const DAMAGE_FACTOR := 1.12`

## Functions

### `ranged_weapon`

```gdscript
static func ranged_weapon(inventory) -> String
```

### `valid_state`

```gdscript
static func valid_state(weapon: Variant, hits: Variant, inventory) -> bool
```

Reject forged hit counts, invalid weapon IDs, lost and unequipped weapons.

### `bonus_active`

```gdscript
static func bonus_active(weapon: String, hits: int, inventory, actual_weapon: String) -> bool
```

