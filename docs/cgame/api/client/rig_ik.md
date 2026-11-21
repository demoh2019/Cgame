# rig_ik.gd

> Procedural rig toolkit (Control-Rig style): two-bone IK with pole vector, FABRIK chains with cone/hinge joint constraints, multi-effector full-body IK with a...

`res://scripts/client/rig_ik.gd`

## Overview

```text
Procedural rig toolkit (Control-Rig style): two-bone IK with pole vector, FABRIK chains with
cone/hinge joint constraints, multi-effector full-body IK with a free pelvis, aim constraint,
and Skeleton3D read/write helpers. Pure math on position arrays so it runs headless.

Credit / licensing: original implementation written for this project. The algorithms follow
the published literature, no third-party source code was copied:
  - FABRIK: Aristidou & Lasenby, "FABRIK: A fast, iterative solver for the inverse kinematics
    problem", Graphical Models 73(5), 2011 (the multi-chain / sub-base averaging scheme and
    joint-constraint projection described there).
  - Two-bone IK: the classic law-of-cosines solution with a pole vector (public domain math,
    as documented e.g. in Inigo Quilez's "two bone IK" article and many engines).
  - Aim: shortest-arc quaternion clamped by a cone angle.
No Apache-2.0 / MIT / BSD source was ported.
```

## Constants

- `const EPS := 0.000001`

## Classes

- `class FullBodyIK extends RefCounted:` - Multi-chain full-body IK (FABRIK tree). Skeleton = parent indices (parents precede children, root/pelvis is bone 0 with parent -1) + rest positions. Effectors {bone, target, weight} are solved simultaneously: the backward pass pulls every chain to its target and averages the sub-base candidates where chains share bones (spine, pelvis), so the pelvis shifts toward the centroid of the demands; the forward pass restores exact bone lengths and joint constraints. Bones not on an effector chain (head, fingers) follow their parent by translation.

## Functions

### `two_bone`

```gdscript
static func two_bone(root: Vector3, mid: Vector3, tip: Vector3, target: Vector3, pole: Vector3) -> Dictionary
```

Two-bone IK. Returns {"mid": Vector3, "tip": Vector3, "reached": bool}. Bone lengths are
preserved; an unreachable target gives a straight limb pointing at it. `pole` is a world
position the middle joint (knee/elbow) is pulled toward.

### `apply_constraint`

```gdscript
static func apply_constraint(prev_dir: Vector3, dir: Vector3, constraint: Dictionary) -> Vector3
```

```text
Limits a bone direction against the previous bone direction. Constraint dictionaries:
{"type": "cone", "angle": rad}  - direction within `angle` of the previous bone direction;
{"type": "hinge", "axis": Vector3, "min": rad, "max": rad} - rotation only around the world
  axis, bend angle relative to the previous direction clamped to [min, max].
```

### `fabrik_chain`

```gdscript
static func fabrik_chain(positions: PackedVector3Array, target: Vector3, iterations: int = 16, tolerance: float = 0.001, constraints: Array = []) -> PackedVector3Array
```

FABRIK on a single chain (root fixed at positions[0]). `constraints[i]` (optional) limits
the direction of bone i->i+1 relative to bone i-1->i; for i == 0 an optional "ref" Vector3
in the dictionary gives the reference direction. Returns the solved positions.

### `aim`

```gdscript
static func aim(bone_pos: Vector3, forward: Vector3, target: Vector3, max_angle: float = PI) -> Quaternion
```

Shortest-arc rotation turning `forward` toward the direction bone_pos -> target, clamped to
`max_angle` radians. Apply as q * forward.

### `pose_from_skeleton`

```gdscript
static func pose_from_skeleton(skeleton: Skeleton3D) -> Dictionary
```

Reads a Skeleton3D into plain arrays: names, parents, global rest positions/rotations and the
current global pose positions.

### `apply_to_skeleton`

```gdscript
static func apply_to_skeleton(skeleton: Skeleton3D, positions: PackedVector3Array) -> void
```

Writes solved global joint positions back to the skeleton as local bone rotations (each
bone is swung from its rest direction toward its first child; leaf bones keep their rest
orientation relative to the parent) plus local positions. Twist about the bone axis is
not recovered. Bones are processed parents first regardless of index order.

### `topo_order`

```gdscript
static func topo_order(parents: PackedInt32Array) -> PackedInt32Array
```

Indices sorted so every parent precedes its children.

_2 private function(s) starting with `_` are not listed._
