# portable_shelter.gd

> (no header comment)

`res://scripts/shared/portable_shelter.gd`

## Constants

- `const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")` - Ephemeral shared storm/cold cover; never a safe zone or permanent fortification.
- `const COST := {"cloth_1": 2, "fiber_1": 2, "plank_1": 1}`
- `const DURATION := 240.0`
- `const COVER_RADIUS := 3.5`
- `const WEATHER_REDUCTION := 0.75`
- `const ANCHORED_WEATHER_REDUCTION := 0.90`
- `const VISUAL_REDUCTION := 0.25`
- `const MIN_VISUAL := 0.35`
- `const MIN_SEPARATION := 4.0`
- `const CANOPY_RADIUS := 0.75`
- `const MAX_GLOBAL := 64`
- `const MAX_PER_OWNER := 1`
- `const PACK_RANGE := 3.2`

## Functions

### `valid_site`

```gdscript
static func valid_site(world, point: Vector2, origin: Vector2, shelters: Dictionary, campfires: Dictionary) -> String
```

### `covers`

```gdscript
static func covers(shelters: Dictionary, position: Vector3, now: float) -> bool
```

### `camouflaged`

```gdscript
static func camouflaged(shelters: Dictionary, position: Vector3, now: float, crouching: bool, noise_seconds: float, alive: bool = true) -> bool
```

Quiet, crouching survivors receive cover only inside a live canvas tarp.

### `visual_signature`

```gdscript
static func visual_signature(base: float, shelters: Dictionary, position: Vector3, now: float, crouching: bool, noise_seconds: float, alive: bool = true) -> float
```

Stack with stance and armor without ever providing complete invisibility.

### `exposure_severity`

```gdscript
static func exposure_severity(severity: float, covered: bool, anchored: bool = false) -> float
```

### `visible`

```gdscript
static func visible(shelters: Dictionary, position: Vector3, now: float, radius: float) -> Array
```

