# stealth_stance.gd

> (no header comment)

`res://scripts/shared/stealth_stance.gd`

## Constants

- `const WALK_MULTIPLIER := 0.55` - Shared crouching rules: vision reduction is not immunity to sound or combat.
- `const VISUAL_MULTIPLIER := 0.60`
- `const MIN_VISUAL := 0.35`

## Functions

### `speed_factor`

```gdscript
static func speed_factor(crouching: bool) -> float
```

### `visual_signature`

```gdscript
static func visual_signature(base: float, crouching: bool, noise_timer: float, alive: bool = true) -> float
```

