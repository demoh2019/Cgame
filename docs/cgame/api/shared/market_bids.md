# market_bids.gd

> Albion Online-style buy orders.

`res://scripts/shared/market_bids.gd`

## Overview

Albion Online-style buy orders. A buyer escrows silver for "N x item at price P";
any seller at the hub can instantly sell into the highest order. Goods go to the
buyer's market deliveries (collected at the hub), the seller is paid at once minus
the usual sales tax. Cancelled or expired orders refund the unspent silver.

## Constants

- `const MarketBoard = preload("res://scripts/shared/market_board.gd")`
- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const MAX_BIDS := 80`
- `const MAX_PER_BUYER := 4`
- `const BID_LIFETIME := 7.0 * 86400.0`

## Functions

### `validate_bid`

```gdscript
static func validate_bid(silver_carried: int, item_id: String, quantity: int, unit_price: int) -> String
```

### `best_first`

```gdscript
static func best_first(a: Dictionary, b: Dictionary) -> bool
```

Highest price first, then oldest (lower id) first.

### `sellable`

```gdscript
static func sellable(inventory, item_id: String) -> int
```

Units of `item_id` a seller can hand over (carried, minus what is equipped).

