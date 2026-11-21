# storm_lightning.gd

> (no header comment)

`res://scripts/shared/storm_lightning.gd`

## Constants

- `const Weather = preload("res://scripts/shared/weather.gd")` - Server-generated, telegraphed environmental lightning during real storms. Hit checks use the actual survivor position at impact, never RPC coordinates.
- `const WorldGen = preload("res://scripts/shared/world_gen.gd")`
- `const WARNING_SECONDS := 2.8`
- `const CHECK_INTERVAL := 55.0`
- `const RETRY_INTERVAL := 10.0`
- `const RADIUS := 4.0`
- `const DAMAGE := 16.0`
- `const MAX_OFFSET := 1.8`
- `const THUNDER_MAX_DISTANCE := 2400.0`
- `const THUNDER_COARSE_GRID := 256.0`

## Functions

### `create_warning`

```gdscript
static func create_warning(world, position: Vector3, now: float) -> Dictionary
```

### `strike_valid`

```gdscript
static func strike_valid(world, strike: Dictionary, now: float) -> bool
```

### `in_blast`

```gdscript
static func in_blast(center: Vector2, position: Vector3) -> bool
```

