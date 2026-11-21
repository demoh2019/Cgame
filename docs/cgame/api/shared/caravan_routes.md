# caravan_routes.gd

> (no header comment)

`res://scripts/shared/caravan_routes.gd`

## Constants

- `const Inventory = preload("res://scripts/shared/inventory.gd")` - Deterministic settlement-to-settlement NPC delivery routes. No client positions, item counts, target IDs or silver rewards are ever trusted. Active jobs save only the source's region/ID and the derived destination ID.
- `const WorldPoi = preload("res://scripts/shared/world_poi.gd")`
- `const RegionalTrade = preload("res://scripts/shared/regional_trade.gd")`
- `const MIN_ROUTE_DISTANCE := 190.0`
- `const MAX_ROUTE_DISTANCE := 900.0`
- `const CARGO_COUNT := 3`
- `const CARGO := {`

## Functions

### `station_at`

```gdscript
static func station_at(world, position: Vector3) -> Dictionary
```

### `offer_for`

```gdscript
static func offer_for(world, source: Dictionary) -> Dictionary
```

Source->destination is immutable for a given world seed and region.
Prefer the closest qualified settlement, then a stable ID on exact ties.

### `saved_state`

```gdscript
static func saved_state(offer: Dictionary) -> Dictionary
```

### `from_saved`

```gdscript
static func from_saved(world, state: Variant) -> Dictionary
```

Rebuild the canonical offer on every save-load, not arbitrary client data.
Saves cannot grant free silver, select another route or fake destinations.

### `valid_state`

```gdscript
static func valid_state(world, state: Variant) -> bool
```

### `deliver`

```gdscript
static func deliver(carried, offer: Dictionary) -> Dictionary
```

Inventory withdrawal plus reward transfer is one atomic server operation.
No reward if goods are missing or the backpack cannot accept the silver.

