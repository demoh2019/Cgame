# foot_locking.gd

> Foot locking with contact phases.

`res://scripts/client/foot_locking.gd`

## Overview

Foot locking with contact phases. Inspired by UE5 Foot Placement / Foot IK and
Unity Animation Rigging two-bone IK foot pinning. Pure math (no nodes) so it can
be tested headless; one instance per character.

## Constants

- `const MAX_STRETCH: float = 0.35` - metres the body may pull a locked foot from the animated pose
- `const BLEND_IN: float = 0.08` - seconds to reach full IK weight after plant
- `const BLEND_OUT: float = 0.2` - seconds to return to the animation after lift-off or release
- `const PLANT_THRESHOLD: float = 0.5`
- `const FEET: Array[String] = ["left", "right"]`

## Documented variables

- `var _locked: Dictionary = {}` - foot -> bool
- `var _released: Dictionary = {}` - foot -> bool (stretched out; no re-lock until lift-off)
- `var _lock_pos: Dictionary = {}` - foot -> Vector3
- `var _weight: Dictionary = {}` - foot -> float

## Functions

### `update`

```gdscript
func update(delta: float, foot_world: Dictionary, contact: Dictionary, ground_height: Callable) -> Dictionary
```

### `pelvis_offset`

```gdscript
static func pelvis_offset(left_target_y: float, right_target_y: float, left_anim_y: float, right_anim_y: float) -> float
```

Lowers the pelvis by the larger negative foot correction so the lower foot can reach.

_1 private function(s) starting with `_` are not listed._
