# outpost_provisions.gd

> (no header comment)

`res://scripts/shared/outpost_provisions.gd`

## Constants

- `const Inventory = preload("res://scripts/shared/inventory.gd")` - Server-authoritative bounded logistics: every captured outpost may receive four survival cargo packs, never infinite ownership extensions.
- `const DELIVERY_RADIUS := 4.0`
- `const EXTRA_SECONDS := 45.0`
- `const MAX_EXTRA_SECONDS := 180.0`
- `const COST := {"canned_food": 2, "water_bottle": 2, "wood_1": 4}`

## Functions

### `deliver`

```gdscript
static func deliver(site: Dictionary, player, authorized: bool, now: float, contested_now: bool) -> Dictionary
```

