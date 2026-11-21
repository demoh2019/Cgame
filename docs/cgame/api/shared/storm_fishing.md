# storm_fishing.gd

> (no header comment)

`res://scripts/shared/storm_fishing.gd`

## Constants

- `const Weather = preload("res://scripts/shared/weather.gd")` - Optional high-risk fishing: server weather, risk and catch sizes only.
- `const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")`
- `const Fishing = preload("res://scripts/shared/fishing.gd")`
- `const CAST_SECONDS := 8.0`
- `const BONUS_FISH := 2`
- `const MIN_FREE_FISH := 3`

## Functions

### `qualifies`

```gdscript
static func qualifies(world, position: Vector3, now: float) -> bool
```

### `bonus_for`

```gdscript
static func bonus_for(backpack, fish_id: String, base_count: int) -> int
```

Other fish quality gates (zone, profession, rod) are unchanged.

