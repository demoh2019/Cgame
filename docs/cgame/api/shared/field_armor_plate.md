# field_armor_plate.gd

> (no header comment)

`res://scripts/shared/field_armor_plate.gd`

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")` - Limited, paid armor preparation against ordinary infected claws.
- `const ITEM_ID := "field_armor_plate"`
- `const HITS := 3`
- `const DAMAGE_FACTOR := 0.80`

## Functions

### `armor_equipped`

```gdscript
static func armor_equipped(inventory) -> String
```

### `valid_state`

```gdscript
static func valid_state(armor: Variant, hits: Variant, inventory) -> bool
```

### `active`

```gdscript
static func active(armor: String, hits: int, inventory) -> bool
```

