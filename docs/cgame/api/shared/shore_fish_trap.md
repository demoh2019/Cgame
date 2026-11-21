# shore_fish_trap.gd

> (no header comment)

`res://scripts/shared/shore_fish_trap.gd`

## Constants

- `const Fishing = preload("res://scripts/shared/fishing.gd")` - Session-only shoreline nets: the server picks water, time and catch tier.
- `const ITEM_ID := "shore_fish_trap"`
- `const CATCH_SECONDS := 120.0`
- `const LIFETIME_SECONDS := 600.0`
- `const COUNT := 2`
- `const COLLECT_RANGE := 4.5`
- `const MIN_SEPARATION := 4.0`
- `const MAX_GLOBAL := 80`

## Functions

### `site`

```gdscript
static func site(world, position: Vector3, traps: Dictionary, now: float) -> Dictionary
```

### `collectable`

```gdscript
static func collectable(position: Vector3, trap: Dictionary) -> bool
```

### `visible`

```gdscript
static func visible(traps: Dictionary, position: Vector3, now: float, radius: float) -> Array
```

