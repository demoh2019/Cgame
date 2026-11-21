# field_smoke.gd

> (no header comment)

`res://scripts/shared/field_smoke.gd`

## Constants

- `const Weather = preload("res://scripts/shared/weather.gd")` - Ephemeral PvE sight cover. Hearing, scent, firelight, PvP and active threat remain unchanged.
- `const ITEM_ID := "smoke_charge"`
- `const DURATION := 9.0`
- `const RADIUS := 4.5`
- `const MULTIPLIER := 0.52`
- `const MIN_VISUAL := 0.35`
- `const COOLDOWN := 18.0`
- `const MAX_GLOBAL := 48`
- `const USE_NOISE_RADIUS := 4.0`
- `const USE_NOISE_SECONDS := 0.5`

## Functions

### `drift`

```gdscript
static func drift(cloud: Dictionary, world, now: float, delta: float) -> Dictionary
```

Advances a paid smoke volume by one authoritative simulation tick. The
centre drifts; sight protection follows the volume, not its cast location.
Water, sanctuary borders and invalid time stop the cloud rather than
letting it cross into safe hubs or disappear for a free re-cast.

### `inside`

```gdscript
static func inside(clouds: Dictionary, position: Vector3, now: float) -> bool
```

### `signature`

```gdscript
static func signature(base: float, clouds: Dictionary, position: Vector3, now: float, noise_seconds: float, alive: bool) -> float
```

### `visible`

```gdscript
static func visible(clouds: Dictionary, position: Vector3, now: float, radius: float) -> Array
```

