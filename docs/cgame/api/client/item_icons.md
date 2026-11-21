# item_icons.gd

> Item icons: one white silhouette per item (game-icons.net, CC BY 3.0, see docs/ASSETS.md), shared by every tier of the item and tinted by the interface.

`res://scripts/client/item_icons.gd`

## Overview

Item icons: one white silhouette per item (game-icons.net, CC BY 3.0, see docs/ASSETS.md), shared by every tier of
the item and tinted by the interface. Unknown items fall back to a neutral crate.

## Constants

- `const DIR := "res://assets/icons/items/"`
- `const FALLBACK := "scrap"`

## Functions

### `base_id`

```gdscript
static func base_id(item_id: String) -> String
```

The item without its tier suffix: "wood_3" -> "wood".

### `icon`

```gdscript
static func icon(item_id: String) -> Texture2D
```

### `kind_color`

```gdscript
static func kind_color(kind: String) -> Color
```

Icon tint by what the item is for, so the backpack reads at a glance: weapons warm, medicine red, food green ...

