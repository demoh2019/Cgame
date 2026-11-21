# wet_clothing.gd

> (no header comment)

`res://scripts/shared/wet_clothing.gd`

## Constants

- `const Weather = preload("res://scripts/shared/weather.gd")` - Persistent wet-clothing simulation driven solely by server weather and the actual positions of field campfires/tarps. 0=dry, 100=soaked.
- `const SOAK_PER_SECOND := 0.9`
- `const AIR_DRY_PER_SECOND := 0.16`
- `const SHELTER_DRY_PER_SECOND := 0.55`
- `const FIRE_DRY_PER_SECOND := 2.5`
- `const MAX_COLD_PENALTY := 0.30`
- `const MAX_WETNESS := 100.0`

## Functions

### `next_wetness`

```gdscript
static func next_wetness(current: float, delta: float, conditions: Dictionary, armor_id: String, under_tarp: bool, near_fire: bool) -> float
```

### `cold_penalty`

```gdscript
static func cold_penalty(wetness: float, conditions: Dictionary, armor_id: String) -> float
```

Wet clothing adds exposure stress only in actual cold, even if the rain
has stopped. Existing camp/tarp protections are applied afterwards.

