# regional_trade.gd

> (no header comment)

`res://scripts/shared/regional_trade.gd`

## Constants

- `const Vendor = preload("res://scripts/shared/vendor.gd")` - Village-specific, deterministic NPC resource demand. The server selects the trade station from world geometry; clients never submit a price.
- `const WorldPoi = preload("res://scripts/shared/world_poi.gd")`
- `const MAX_PREMIUM_PERCENT := 75`
- `const FOCUS := ["fish", "ore", "fiber", "wood", "stone"]`

## Functions

### `category`

```gdscript
static func category(item_id: String) -> String
```

### `offer_for_site`

```gdscript
static func offer_for_site(site: Dictionary) -> Dictionary
```

### `local_offer`

```gdscript
static func local_offer(world, position: Vector3) -> Dictionary
```

Valid only while actually standing beside the procedurally generated
trader/workbench. The central safe hub retains ordinary vendor prices.

### `sell_price`

```gdscript
static func sell_price(item_id: String, offer: Dictionary) -> int
```

### `public_offer`

```gdscript
static func public_offer(world, position: Vector3) -> Dictionary
```

