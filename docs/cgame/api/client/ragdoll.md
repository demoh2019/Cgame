# ragdoll.gd

> Runtime ragdolls for dead infected — the equivalent of Unity ragdoll joints / Unreal Physics Asset death simulation, built from the engine's PhysicalBoneSimu...

`res://scripts/client/ragdoll.gd`

## Overview

Runtime ragdolls for dead infected — the equivalent of Unity ragdoll joints /
Unreal Physics Asset death simulation, built from the engine's
PhysicalBoneSimulator3D. Bodies are generated at runtime from whichever
mannequin bones the model has, collide only with a small heightmap patch of
the terrain under the corpse (own collision layer), and are capped per tier.

## Constants

- `const LAYER := 1 << 19`
- `const BUDGET := [0, 3, 6, 12] # Low, Medium, High, Ultra.`
- `const SETTLE_SECONDS := 5.0`
- `const SINK_SECONDS := 1.5`
- `const PATCH := 9 # Heightmap samples per side, 1 m apart.`
- `const BONES := {` - bone -> [tip bone, radius in metres before model scale, joint type, swing/hinge span degrees]

## Functions

### `budget`

```gdscript
static func budget(level: int) -> int
```

### `present_bones`

```gdscript
static func present_bones(skeleton: Skeleton3D) -> Array[String]
```

Which ragdoll bones this skeleton actually has (models without a mannequin rig get none).

### `segment`

```gdscript
static func segment(skeleton: Skeleton3D, bone: String) -> Vector3
```

Capsule length/orientation between a bone and its tip in the bone's rest space.

### `patch_heights`

```gdscript
static func patch_heights(x: float, z: float, center_y: float, height_at: Callable) -> PackedFloat32Array
```

Heights (relative to `center_y`) for a PATCH×PATCH grid around (x, z).

### `build`

```gdscript
static func build(skeleton: Skeleton3D) -> PhysicalBoneSimulator3D
```

Builds bodies on the skeleton and a ground patch next to it; returns the simulator or null.

### `ground_patch`

```gdscript
static func ground_patch(x: float, ground_y: float, z: float, height_at: Callable) -> StaticBody3D
```

A heightmap collider for the terrain under the corpse, on the ragdoll layer only.

