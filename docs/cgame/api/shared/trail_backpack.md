# trail_backpack.gd

> (no header comment)

`res://scripts/shared/trail_backpack.gd`

## Constants

- `const ITEM_ID := "trail_backpack_2"` - A physical T2 pack distributes finite on-foot carry load. It never grants inventory slots, removes mass, prevents PvP drops or stacks with panniers.
- `const SUPPORTED_KG := 14.0`

## Functions

### `installed`

```gdscript
static func installed(inventory) -> bool
```

### `support_kg`

```gdscript
static func support_kg(inventory, mounted: bool = false) -> float
```

### `effective_weight`

```gdscript
static func effective_weight(inventory) -> float
```

