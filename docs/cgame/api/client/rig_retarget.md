# rig_retarget.gd

> Runtime IK retargeting between humanoid skeletons of different proportions: bone-name mapping (Mixamo / Unreal mannequin / Quaternius / generic), local-rotat...

`res://scripts/client/rig_retarget.gd`

## Overview

Runtime IK retargeting between humanoid skeletons of different proportions: bone-name
mapping (Mixamo / Unreal mannequin / Quaternius / generic), local-rotation transfer with
root translation scaled by the leg-length ratio, and two-bone foot IK to keep contact.

Credit / licensing: original implementation. The approach (name-map + rotation transfer +
hips scaled by leg-length ratio + foot IK correction) follows the general technique used by
engine retargeters (e.g. Unreal IK Retargeter, Unity Humanoid/Mecanim avatars) as described in
their public documentation; no source code from those or any other project was copied or ported.
No Apache-2.0 / MIT / BSD code is included.

Rig dictionary: {"names": PackedStringArray, "parents": PackedInt32Array (parents precede
children), "rest": PackedVector3Array (global rest joint positions),
"rest_rot": Array[Quaternion] (optional local rest rotations, default identity)}.
Pose dictionary: {"rot": Array[Quaternion] local rotations relative to rest, "hips": Vector3
global hips position}.

## Constants

- `const RigIK = preload("res://scripts/client/rig_ik.gd")`
- `const _BASE_ALIASES := {`

## Functions

### `canonical`

```gdscript
static func canonical(bone_name: String, aliases: Dictionary = {}) -> String
```

Canonical key for a bone name, e.g. "mixamorig:LeftUpLeg" -> "upperleg|l". Empty if unknown.

### `build_map`

```gdscript
static func build_map(source_names: PackedStringArray, target_names: PackedStringArray, aliases: Dictionary = {}) -> Dictionary
```

Maps source bone index -> target bone index by canonical humanoid name (with identical raw
names as a fallback). `aliases` may map raw names (or normalised lower-case base names) to a
canonical key such as "hand|l" for custom rigs.

### `find_bone`

```gdscript
static func find_bone(names: PackedStringArray, key: String, aliases: Dictionary = {}) -> int
```

Index of the bone with a canonical key ("hips", "foot|l", ...), or -1.

### `fk`

```gdscript
static func fk(rig: Dictionary, rots: Array, hips_bone: int, hips: Vector3) -> Dictionary
```

Forward kinematics. Returns {"pos": PackedVector3Array, "rot": Array[Quaternion] (global)}.
`hips_bone` is placed at `hips`; everything else derives from rest offsets and rotations.

### `retarget_pose`

```gdscript
static func retarget_pose(source_rest: Dictionary, source_pose: Dictionary, target_rest: Dictionary, map: Dictionary) -> Dictionary
```

Transfers local rotations through `map` (source idx -> target idx) and scales the hips
position by the leg-length ratio (horizontal travel scaled, vertical offset from the rest
height scaled). Unmapped target bones stay at rest. Returns {"rot", "hips", "ratio"}.

### `ik_correct_feet`

```gdscript
static func ik_correct_feet(target_rig: Dictionary, pose: Dictionary, foot_targets: Dictionary) -> Dictionary
```

Keeps foot contact: for each {target foot bone index: world position} two-bone IK is run on
the leg (upper leg, lower leg, foot) with the current knee as the pole vector, and the local
rotations of both leg bones are rewritten (foot keeps its global orientation). Returns
{"rot", "hips", "pos" (global joint positions), "error" (max foot miss)}.

_4 private function(s) starting with `_` are not listed._
