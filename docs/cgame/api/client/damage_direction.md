# damage_direction.gd

> Damage direction indicator (Call of Duty / Fortnite): a red arc at the screen edge points to whoever just hit you, relative to the camera, and fades out.

`res://scripts/client/damage_direction.gd`

## Overview

Damage direction indicator (Call of Duty / Fortnite): a red arc at the screen
edge points to whoever just hit you, relative to the camera, and fades out.
Uses only the server's hit event ("by" attacker id) and snapshot positions.

## Constants

- `const LIFE := 1.3`
- `const MAX_ARCS := 4`

## Functions

### `screen_angle`

```gdscript
static func screen_angle(me: Vector3, target: Vector3, cam_basis: Basis) -> float
```

Screen angle (radians, 0 = up/ahead, clockwise) of `target` from `me` for a camera basis.

### `on_hit`

```gdscript
func on_hit(attacker_world: Vector3, damage: float) -> void
```

### `update_view`

```gdscript
func update_view(me: Vector3, delta: float) -> void
```

_2 private function(s) starting with `_` are not listed._
