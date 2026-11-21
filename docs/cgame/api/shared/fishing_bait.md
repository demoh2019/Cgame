# fishing_bait.gd

> Optional, item-paid shoreline bait.

`res://scripts/shared/fishing_bait.gd`

## Overview

Optional, item-paid shoreline bait. One unit is spent only if the server
can deliver the bonus fish on a completed, valid cast. The client cannot
choose fish tier, reward count or cast duration.

## Constants

- `const ITEM_ID := "shore_bait"`
- `const BONUS_FISH := 1`

## Functions

### `can_request`

```gdscript
static func can_request(backpack) -> bool
```

### `spend_for_bonus`

```gdscript
static func spend_for_bonus(backpack, fish_id: String, base_amount: int, requested: bool) -> bool
```

Returns whether a real bait was consumed. Reserve enough fish capacity
before deducting anything; unbaited and partially-full casts stay normal.

