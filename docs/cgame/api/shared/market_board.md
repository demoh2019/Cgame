# market_board.gd

> Server-authoritative market board.

`res://scripts/shared/market_board.gd`

## Overview

Server-authoritative market board. Listing moves the goods into escrow; buyers pay
even while the seller is offline, and proceeds/unsold goods are collected at the hub.
Escrow is saved with the world checkpoint (signed-in accounts only).

Market sales burn a bounded seller-side commission as a silver sink.
Direct player barter remains untaxed.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const Inventory = preload("res://scripts/shared/inventory.gd")`
- `const MAX_QUANTITY := 40`
- `const MAX_UNIT_PRICE := 2000`
- `const MAX_LISTINGS := 80`
- `const MAX_PER_SELLER := 4`
- `const LISTING_LIFETIME := 7.0 * 86400.0 # Escrowed listings last a week.`
- `const SALE_TAX_PERCENT := 3`

## Functions

### `sale_tax`

```gdscript
static func sale_tax(total: int) -> int
```

### `listed_quantity`

```gdscript
static func listed_quantity(orders: Dictionary, seller_id: int, item_id: String) -> int
```

Listings promise real carried stock without removing it. Multiple adverts
from the same seller cannot collectively promise more than their backpack
contains, while separate sellers and items remain independent.

### `unlisted_stock`

```gdscript
static func unlisted_stock(carried, orders: Dictionary, seller_id: int, item_id: String) -> int
```

### `cheaper_first`

```gdscript
static func cheaper_first(a: Dictionary, b: Dictionary) -> bool
```

Browse by item then cheapest unit price, with stable older-listing precedence.
Sorting is purely presentational; purchase still uses the original listing ID.

### `validate_listing`

```gdscript
static func validate_listing(carried, item_id: String, quantity: int, unit_price: int) -> String
```

### `purchase`

```gdscript
static func purchase(buyer, seller, listing: Dictionary, quantity: int) -> Dictionary
```

Revalidate BOTH backpacks at settlement. All item and silver transfers,
including the tax burn, happen on staged inventories and only commit together.
Unlike a gross-first barter transfer this also handles the silver-stack edge:
a seller may have room for net proceeds but not for the untaxed gross total.

### `purchase_from_escrow`

```gdscript
static func purchase_from_escrow(buyer, listing: Dictionary, quantity: int) -> Dictionary
```

Escrow sale: the listing already holds the goods, so only the buyer's backpack changes.
Staged, so a failed payment or a full backpack leaves everything unchanged.

