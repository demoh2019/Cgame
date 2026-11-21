# siege_defusal.gd

> (no header comment)

`res://scripts/shared/siege_defusal.gd`

## Constants

- `const Structures = preload("res://scripts/shared/structures.gd")` - A counterplay action against a real four-second armed siege explosive. All targeting and wall ownership come from server state, never the RPC.
- `const SiegeCharge = preload("res://scripts/shared/siege_charge.gd")`
- `const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")`
- `const RangedCover = preload("res://scripts/shared/ranged_cover.gd")`
- `const ITEM_ID := "siege_defusal_kit"`
- `const REACH := 3.0`

## Functions

### `nearest`

```gdscript
static func nearest(world, player, charges: Dictionary, walls: Dictionary, now: float) -> Dictionary
```

