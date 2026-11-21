# wind_hearing.gd

> (no header comment)

`res://scripts/shared/wind_hearing.gd`

## Constants

- `const MIN_WIND_SPEED := 0.4` - Deterministic directional hearing: only real, server-created sound travels farther downwind and less far upwind. Sight, scent and earned aggro stay intact.
- `const FULL_WIND_SPEED := 1.6`
- `const MAX_DIRECTIONAL_CHANGE := 0.25`

## Functions

### `radius`

```gdscript
static func radius(noise: float, wind: Vector2, source: Vector2, listener: Vector2, leash: float) -> float
```

Source and listener are authoritative horizontal world positions.
No noise can be created from silence and no detection escapes the leash.

