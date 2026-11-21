# character_anim_modifier.gd

> Procedural layer applied after the AnimationPlayer (Unity Animation Rigging / Unreal Control Rig equivalent): breathing, lean into turns, additive flinch, he...

`res://scripts/client/character_anim_modifier.gd`

## Overview

Procedural layer applied after the AnimationPlayer (Unity Animation Rigging / Unreal Control Rig equivalent):
breathing, lean into turns, additive flinch, head look-at, pelvis drop and two-bone foot IK on slopes.
Idempotent: bones it touched are restored before the next pass, so skipped frames never accumulate.

## Constants

- `const Anim = preload("res://scripts/client/character_anim.gd")`

## Documented variables

- `var estimated_full_pose_us: int = 0` - EMA of the optional full-pose SkeletonModifier script pass only; this excludes animation mixer, GPU skinning and native FootPlacement costs.

## Functions

### `kick`

```gdscript
func kick(local_dir: Vector3, strength: float) -> void
```

Additive hit reaction; `strength` ~0.5 light, ~1 heavy. `local_dir` in body space (from the attacker).

### `bone`

```gdscript
func bone(name: String) -> int
```

### `is_resolved`

```gdscript
func is_resolved() -> bool
```

### `reset`

```gdscript
func reset() -> void
```

Undoes every pose change made so far (used when the character drops to a cheap LOD tier or starts a ragdoll).

_6 private function(s) starting with `_` are not listed._
