# vendor.gd

> Authoritative NPC vendor: sell scavenged materials for silver and buy basic survival supplies at the existing safe hub workbench.

`res://scripts/shared/vendor.gd`

## Overview

Authoritative NPC vendor: sell scavenged materials for silver and buy
basic survival supplies at the existing safe hub workbench.
A valid trade is simulated on a private inventory copy and committed
only when both the debit and the credit fully fit.

## Constants

- `const Inventory = preload("res://scripts/shared/inventory.gd")`
- `const Reputation = preload("res://scripts/shared/reputation.gd")`
- `const PvpInfamy = preload("res://scripts/shared/pvp_infamy.gd")`
- `const MAX_QUANTITY := 50`
- `const BUY_PRICES := {`
- `const SELL_PRICES := {`
- `const REFINED_PRIORITY := ["bar_4", "bar_3", "bar_2", "bar_1",` - Refining raises the NPC sale value, connecting professions with salvage. Prefer a refined item when selling one carried material from a shortcut.
- `const FISH_PRIORITY := ["raw_fish_4", "raw_fish_3", "raw_fish_2", "raw_fish"]` - Prefer the rarest fish first so returning fishers can cash out valuable catches without affecting the existing material-salvage shortcut.

## Functions

### `first_fish`

```gdscript
static func first_fish(carried) -> String
```

### `first_sellable`

```gdscript
static func first_sellable(carried) -> String
```

### `transact`

```gdscript
static func transact(carried, item_id: String, quantity: int, buy: bool, renown: int = 0, infamy: float = 0.0, sell_quote: int = 0) -> Dictionary
```

