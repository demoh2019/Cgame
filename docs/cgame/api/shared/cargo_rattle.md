# cargo_rattle.gd

> Weight makes walking under a heavy backpack conspicuous in the wilderness.

`res://scripts/shared/cargo_rattle.gd`

## Overview

Weight makes walking under a heavy backpack conspicuous in the wilderness.
The authoritative server computes both load and real distance travelled.
No client-defined noise, extra inventory slots, or persistent modifiers.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const NOISE_SECONDS := 0.7`
- `const MIN_RADIUS := 10.0`
- `const MAX_RADIUS := 24.0`

## Functions

### `radius`

```gdscript
static func radius(movement_factor: float, moved_meters: float, crouching: bool, mounted: bool) -> float
```

Returns server-created detection radius, or zero when there is no
actual movement, load penalty, or when the traveler crouches / rides.
The returned radius is combined with other sounds using max(), never added.

