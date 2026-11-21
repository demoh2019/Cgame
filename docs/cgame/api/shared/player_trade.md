# player_trade.gd

> All-or-nothing player-to-player barter.

`res://scripts/shared/player_trade.gd`

## Overview

All-or-nothing player-to-player barter. Operates only on server-owned inventories;
both inventories are copied first, and neither original changes on a rejected trade.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const Inventory = preload("res://scripts/shared/inventory.gd")`
- `const MAX_OFFER_LINES := 4`

## Functions

### `validate_offer`

```gdscript
static func validate_offer(items: Dictionary, inventory) -> String
```

### `exchange`

```gdscript
static func exchange(first, second, first_offer: Dictionary, second_offer: Dictionary) -> Dictionary
```

Both offers are maps {item_id: amount}, including silver as an ordinary item.
Does not create or destroy items, including currency, on success or failure.

