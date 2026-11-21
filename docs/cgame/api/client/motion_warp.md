# motion_warp.gd

> Motion Warping for melee (UE5 Motion Warping / "magnetism" in action RPGs): during the wind-up of a swing the visual model glides a short way toward the enem...

`res://scripts/client/motion_warp.gd`

## Overview

Motion Warping for melee (UE5 Motion Warping / "magnetism" in action RPGs):
during the wind-up of a swing the visual model glides a short way toward
the enemy in front of it and turns to face it (orientation warping), then
eases back to the server-owned position. Purely cosmetic: the server's
authoritative position and hit test never move.

## Constants

- `const MAX_SLIDE := 0.45 # Metres of visual lunge.`
- `const CONE_DOT := 0.5 # About 60 degrees either side of the swing.`
- `const SEARCH_EXTRA := 1.2 # Look a little past weapon reach for a target.`
- `const LUNGE_SECONDS := 0.14`
- `const RETURN_SECONDS := 0.26`
- `const STOP_SHORT := 0.75 # Never slide into the target's body.`

## Functions

### `solve`

```gdscript
static func solve(origin: Vector3, direction: Vector2, reach: float, targets: Array) -> Dictionary
```

Returns {"offset": Vector3 (world, horizontal), "yaw": float} or {} when nothing to warp to.

### `play`

```gdscript
static func play(model: Node3D, world_offset: Vector3) -> void
```

Animates a model node's local offset out and back. Safe to call repeatedly.

