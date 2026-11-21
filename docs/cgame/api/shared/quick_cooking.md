# quick_cooking.gd

> (no header comment)

`res://scripts/shared/quick_cooking.gd`

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")` - A recipe suggestion only. The server remains authoritative about stations, surviving, inventory mutations, quantity and permanent crafting mastery.

## Functions

### `best_recipe`

```gdscript
static func best_recipe(inventory, crafting_level: int) -> String
```

Highest tier first. Skips locked recipes or missing ingredients, but never
substitutes a field campfire for the required server-side station check.

