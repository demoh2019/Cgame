# ember_flask.gd

> (no header comment)

`res://scripts/shared/ember_flask.gd`

## Constants

- `const NoiseDecoy = preload("res://scripts/shared/noise_decoy.gd")` - Server-authoritative PvE fire field from a paid thrown consumable.
- `const RangedCover = preload("res://scripts/shared/ranged_cover.gd")`
- `const ITEM_ID := "ember_flask"`
- `const RADIUS := 3.0`
- `const DURATION := 6.0`
- `const TICK_SECONDS := 1.0`
- `const DAMAGE_PER_TICK := 8.0`
- `const MAX_TARGETS_PER_TICK := 4`
- `const MAX_ACTIVE := 16`
- `const MAX_PER_OWNER := 2`
- `const COOLDOWN_SECONDS := 12.0`
- `const NOISE_RADIUS := 19.0`
- `const NOISE_SECONDS := 1.5`
- `const MAX_HEIGHT := 2.5`

## Functions

### `landing`

```gdscript
static func landing(world, origin: Vector3, direction: Vector2) -> Dictionary
```

### `make_pool`

```gdscript
static func make_pool(id: int, site: Dictionary, owner: int, now: float) -> Dictionary
```

### `remaining`

```gdscript
static func remaining(pool: Dictionary, now: float) -> float
```

### `public_state`

```gdscript
static func public_state(pool: Dictionary, now: float) -> Dictionary
```

### `affects`

```gdscript
static func affects(world, center: Vector2, target: Vector3) -> bool
```

Cover, height, safe zones and radius are checked for every damage tick.

