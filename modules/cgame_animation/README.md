# Cgame animation (native ports of the GDScript animation libraries)

This optional built-in 3D module ports the Cgame GDScript animation libraries (`scripts/client/motion_matching.gd`, `foot_locking.gd`, `distance_matching.gd`, `motion_warp.gd`, `rig_ik.gd`, `rig_retarget.gd`, `constraint_graph.gd`, `mocap_cleanup.gd`, `facial_animation.gd`, `lip_sync.gd`) to native code integrated with Godot's animation system. It is available whenever 3D is enabled.

## Classes

| Class | Base | Replaces |
| --- | --- | --- |
| `CgameMotionMatchingDatabase` | `Resource` | `motion_matching.gd`, `motion_db_builder.gd` |
| `AnimationNodeMotionMatching` | `AnimationRootNode` | (new) AnimationTree node driven by the database |
| `FootLockModifier3D` | `SkeletonModifier3D` | `foot_locking.gd` |
| `FullBodyIKModifier3D` | `SkeletonModifier3D` | `RigIK.FullBodyIK` |
| `CgameAimModifier3D` | `SkeletonModifier3D` | `RigIK.aim` |
| `ConstraintGraphModifier3D` | `SkeletonModifier3D` | `constraint_graph.gd` |
| `CgameRigIK` | `RefCounted` | `RigIK.two_bone`, `fabrik_chain`, `aim` (static) |
| `CgameLocomotionTools` | `RefCounted` | `distance_matching.gd`, `motion_warp.gd` solver |
| `CgameRetargeter` | `RefCounted` | `rig_retarget.gd` plus direct `Skeleton3D` pose transfer |
| `CgameMocapCleanup` | `RefCounted` | `mocap_cleanup.gd` (static) |
| `CgameLipSync` | `RefCounted` | `lip_sync.gd` (static) |
| `CgameFacialAnimation` | `RefCounted` | `facial_animation.gd` |

Not duplicated on purpose: the engine already ships `TwoBoneIK3D` (two-bone IK with pole), `FABRIK3D` and an `AimModifier3D`. `CgameAimModifier3D` has a different name because `AimModifier3D` is an unrelated bone constraint; `RigIK.two_bone` stays available as the position-level `CgameRigIK.two_bone`.

## Motion matching

`CgameMotionMatchingDatabase` stores a 24 dimensional feature per frame (root velocity and facing, three trajectory samples, foot positions and velocities), normalizes it and builds a k-means bucket index. `search()` prunes buckets with the triangle inequality, so it returns exactly what `brute_force_search()` returns while testing far fewer frames. A continuing-pose bias favors the next frame of the clip that is already playing.

```gdscript
var db := CgameMotionMatchingDatabase.build_default_database()   # or add_clip()/build() with mocap features
var mm := AnimationNodeMotionMatching.new()
mm.database = db
mm.clip_animations = {"walk_forward": &"walk", "run_forward": &"run"}  # clip name -> animation name
animation_tree.tree_root = mm
animation_tree["parameters/desired_velocity"] = Vector2(0.0, 3.0)
```

The node searches every `search_interval` seconds, plays the chosen clip at the matched time and crossfades for `blend_time`. Query parameters: `velocity`, `facing`, `desired_velocity`, `desired_facing`, `left_foot`, `right_foot`, `left_foot_velocity`, `right_foot_velocity`, or a complete 24 float `features` array. The selection is reported in the read-only `current_clip` and `last_cost` parameters.

## Skeleton modifiers

All modifiers derive from `SkeletonModifier3D`, so they run after the `AnimationTree` / `AnimationPlayer` and honor `influence`.

- `FootLockModifier3D`: plants a foot while its contact value is above `plant_threshold`, releases it when the body stretches it more than `max_stretch`, blends in and out, runs two-bone leg IK and optionally lowers the pelvis. Feed `left_contact` / `right_contact` from animation tracks or script; provide `ground_height` or `ground_height_callback`.
- `FullBodyIKModifier3D`: multi-effector FABRIK over the subtree below `root_bone`, with cone/hinge joint limits.
- `CgameAimModifier3D`: aims a bone axis at a node or position with a maximum angle.
- `ConstraintGraphModifier3D`: ordered list of data-driven constraints (`two_bone`, `fabrik_chain`, `aim`, `copy_rotation`, `limit_rotation`) with JSON import/export. The evaluator is also usable offline through `evaluate_pose()`.

## Tests

`tests/test_cgame_animation.h` holds doctest cases for the pure math: indexed search against brute force, tag filtering and the continuing bias, spring prediction, two-bone reach, FABRIK convergence, joint limits, the multi-effector solver, the One Euro filter, Butterworth, spike removal, key reduction, contact detection, viseme timelines, facial determinism, the foot lock state machine, locomotion helpers and bone-name canonicalization. Run them with `./bin/godot... --test --test-case="*CgameAnimation*"`.

## Script facades

`game_facade/*.gd` wrap every class with the original GDScript as a fallback, so game code works on engine builds without this module (see `CgameAnimNative`).

## Limitations

- The modifiers write rotations only; translation of the solved root (for example the hips) is never changed except for the optional pelvis drop in `FootLockModifier3D`.
- `FullBodyIKModifier3D` applies one aim per solved child at branching bones, so asymmetric poses converge approximately.
- `CgameMotionMatchingDatabase.prune_redundant()` is not serialized; it is recomputed from the stored clips.
- `AnimationNodeMotionMatching` does not inertialize; it crossfades. Clip lengths come from the animation when it exists in the mixer, otherwise from the database.
