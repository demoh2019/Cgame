# hand_flare.gd

> (no header comment)

`res://scripts/shared/hand_flare.gd`

## Constants

- `const WorldCycle = preload("res://scripts/shared/world_cycle.gd")` - Fuel-paid night illumination. Server time and authenticated position only.
- `const ITEM_ID := "signal_flare"`
- `const BURN_SECONDS := 120.0`
- `const INFECTED_NOTICE := 28.0`

## Functions

### `ignite_reason`

```gdscript
static func ignite_reason(seconds: float, now: float, position: Vector3, safe: bool) -> String
```

### `lit`

```gdscript
static func lit(seconds: float, alive: bool) -> bool
```

### `infected_radius`

```gdscript
static func infected_radius(seconds: float, alive: bool, night: bool, safe: bool) -> float
```

### `remaining`

```gdscript
static func remaining(seconds: float, delta: float) -> float
```

