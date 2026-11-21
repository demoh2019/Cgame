# Engine foot placement and stride warping

Status: written statically, NOT YET COMPILED. The classes below do not exist in the current editor binary; the game
detects them at runtime (`EngineFeatures.has`) and skips the feature until the engine is rebuilt.

## What

- `FootPlacementModifier3D` (`scene/3d/foot_placement_modifier_3d.*`): a `SkeletonModifier3D` that plants feet on uneven
  ground. Per leg it samples the ground under the animated foot, moves the foot by the height difference to the ground
  under the skeleton origin, solves thigh/calf analytically (law of cosines, knee direction taken from the animated
  pose), and tilts the foot to the ground normal (3 height samples, clamped by `max_foot_angle`). The pelvis is lowered
  by the largest negative leg offset (clamped by `max_pelvis_offset`, smoothed by `pelvis_interp_speed`).
- `StrideWarpingModifier3D` (`scene/3d/stride_warping_modifier_3d.*`): scales the horizontal (skeleton-space XZ) foot
  offsets from the pelvis by `stride_scale` (= actual speed / animation speed, clamped) and re-solves the legs, so feet
  do not slide when playback speed is clamped.

Equivalents: Unreal "Foot Placement" / "Leg IK" and "Stride Warping"; Unity Animation Rigging "Two Bone IK" ground
alignment. Not implemented: orientation warping, per-foot locking phases, foot-lift weighting by animation curves.

## API

FootPlacementModifier3D
- `pelvis_bone: String`, legs via `add_leg(thigh, calf, foot, foot_height_offset = 0.0)` / `leg_count` +
  `legs/N/{thigh_bone,calf_bone,foot_bone,foot_height_offset}`, `clear_legs()`.
- Ground source: `ground_height_callback: Callable(x: float, z: float) -> float` (world space; wins when valid), else
  `use_raycast` with `collision_mask`, `ray_length`, `ray_start_height`.
- `max_pelvis_offset` (0.4), `pelvis_interp_speed` (12), `max_foot_angle` (40 deg), `align_foot_to_ground` (true),
  `normal_sample_distance` (0.15), `get_current_pelvis_offset()`, `reset()`; inherits `active` and `influence`.
- Static, bound to scripts: `solve_two_bone_angles(upper_len, lower_len, target_dist) -> Vector2(hip, knee)` and
  `pelvis_offset(leg_offsets: PackedFloat32Array, max_offset) -> float` (zero or negative).
- C++ only: `ground_normal_from_samples`, `clamped_alignment`, `solve_leg(skeleton, thigh, calf, foot, target_skel)`.

StrideWarpingModifier3D
- `pelvis_bone`, `add_leg(thigh, calf, foot)`, `stride_scale`, `min_stride_scale` (0.5), `max_stride_scale` (2.0),
  `set_speeds(actual, animation)`, static `compute_stride_scale(...)` and `warp_foot_position(foot, pelvis, scale)`.

Assumptions: skeleton Y is up in skeleton space; the skeleton origin stands on the ground; modifiers run after the
animation (standard SkeletonModifier3D order, place them as children of the `Skeleton3D`).

## Game usage

- `CharacterModel.enable_foot_placement(height_at: Callable) -> bool` instantiates `FootPlacementModifier3D` with
  `ClassDB.instantiate` under the skeleton as `FootPlacement` (bones `pelvis`, `thigh_l/r`, `calf_l/r`, `foot_l/r`) and
  configures it with `set()` / `call()`. Returns false when the class or bones are missing.
- `CharacterModel.disable_foot_placement()` is called from `start_ragdoll`.
- `entity_view.gd` calls it for every player/zombie model when `GraphicsQuality.level() >= 2` (High, Ultra), passing
  `_world.height_at` (= `client.world.height_at`). Distance gating is not done at creation time; the animation LOD
  system can additionally toggle `active` for far models.

## Native foot placement profiling and crowd pose LOD

Cgame's `FootPlacementModifier3D` now has optional, opt-in CPU telemetry:
`profiling_enabled` (default off), `get_last_process_cost_us()`,
`get_estimated_process_cost_us()`, `get_process_sample_count()`,
`reset_process_telemetry()` and static `smooth_process_cost_us()`.
The timer encompasses the **actual native FootPlacement update**, including
ground callbacks / raycasts, leg solving, and foot normal queries. It does
*not* cover GPU skinning, the AnimationMixer or the game server. The output
is bounded to 1–100,000 µs and smoothed with an integer 1/4 EMA, suitable
for planning, not a guaranteed frame deadline. Invalid/missing/no-op samples
never claim zero cost for a completed update. Profiling is off unless an
owner explicitly enables it.

The Albion After `CharacterModel.enable_foot_placement()` path enables
profiling only on supporting Cgame builds, caches the live modifier node,
and sets native `active` according to the **same tier-0 full procedural IK**
budget already applied to the scripted `CharacterAnimModifier`. Tier 1
keeps base animation at full rate without optional Foot Placement; tiers
2–4 additionally follow their existing reduced AnimationMixer rates.
Native IK is also turned off for ragdolls and reconfigured/reused models
cannot accidentally inherit stale modifier references.

The game exposes `CharacterModel.estimated_full_pose_cost_us()`, combining
the measured scripted full-pose cost with native FootPlacement cost when
that native getter exists. `CharacterAnim.apply_crowd()` feeds the combined
estimate to the existing cost-only tier-0 limiter after visibility, distance,
IK retention and combat-pose retention have been selected. The estimate is
saturated at 100,000 µs. Older Cgame builds simply omit native cost
telemetry, while stock Godot uses scripted IK/fallback budgeting.

The timing API intentionally measures **only FootPlacement**, not all
skeletal animation. Animation Budget Allocator concepts:
https://dev.epicgames.com/documentation/unreal-engine/animation-budget-allocator-in-unreal-engine

## Verify after rebuild

1. Build the editor, run `tests/scene/test_foot_placement_modifier_3d.cpp` (`--test --test-case="*FootPlacement*"`).
2. Run `--doctool` to check `doc/classes/FootPlacementModifier3D.xml` and `StrideWarpingModifier3D.xml`.
3. In game on a slope: no leg stretching, feet follow the terrain, pelvis dips on stairs-like steps, ragdoll unaffected.
4. Confirm the pose written with `set_bone_pose_rotation` is not overwritten by later modifiers (e.g. AnimModifier).
