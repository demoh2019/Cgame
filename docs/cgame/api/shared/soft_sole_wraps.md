# soft_sole_wraps.gd

> (no header comment)

`res://scripts/shared/soft_sole_wraps.gd`

## Constants

- `const ITEM_ID := "soft_sole_wraps"` - Server-issued temporary footstep muffling; sound is not invisibility.
- `const DURATION_SECONDS := 90.0`
- `const SPRINT_NOISE_FACTOR := 0.55`

## Functions

### `valid_remaining`

```gdscript
static func valid_remaining(seconds: Variant) -> bool
```

### `sprint_noise`

```gdscript
static func sprint_noise(normal_radius: float, seconds: float) -> float
```

Affects only NEW sprint noise; never reduce an already loud sound source.

