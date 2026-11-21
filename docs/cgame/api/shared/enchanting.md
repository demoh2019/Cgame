# enchanting.gd

> Albion-style enchanting: infected drop runes, elites souls, raid bosses relics.

`res://scripts/shared/enchanting.gd`

## Overview

Albion-style enchanting: infected drop runes, elites souls, raid bosses relics.
At a workbench they raise a piece of gear one level (.0 -> .1 -> .2 -> .3),
swapping the item for its stronger variant (Defs.enchanted_id). Durability and
the equipped slot carry over. All authority stays on the server.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`

## Functions

### `material_drop`

```gdscript
static func material_drop(zone: int, elite: bool, raid_boss: bool, rng: RandomNumberGenerator) -> Dictionary
```

Enchantment materials dropped by a kill. Riskier zones drop more.

### `enchant`

```gdscript
static func enchant(inventory, item_id: String) -> Dictionary
```

Enchants one carried `item_id` in `inventory`. Returns {"ok", "item"} or {"ok": false, "reason", ...}.

