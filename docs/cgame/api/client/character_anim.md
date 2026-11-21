# character_anim.gd

> Pure, unit-testable helpers for procedural character animation (foot IK, look-at, lean, breathing, additive flinch, upper-body layering, animation LOD).

`res://scripts/client/character_anim.gd`

## Overview

Pure, unit-testable helpers for procedural character animation (foot IK, look-at, lean, breathing, additive
flinch, upper-body layering, animation LOD). The runtime driver is character_anim_modifier.gd.

## Constants

- `const UP := Vector3.UP`
- `const CombatAnimationPriority = preload("res://scripts/client/combat_animation_priority.gd")`
- `const NEAR_CAMERA_VISIBILITY_RADIUS := 3.0 # Matches the animation LOD close-camera safeguard.`
- `const IK_RETENTION_HYSTERESIS_METRES := 1.5 # Keeps a prior on-screen IK owner during small camera moves.`
- `const FULL_POSE_CPU_BUDGET_US := [0, 750, 1500, 2750]`
- `const POSE_PROCESS_TARGET_US := 12500 # Main-thread process time, not FPS or GPU frame duration.`
- `const UPPER_PREFIXES := ["spine", "neck", "head", "clavicle", "upperarm", "lowerarm", "hand", "thumb", "index", "middle",`

## Functions

### `reset_adaptive_pose_budget`

```gdscript
static func reset_adaptive_pose_budget() -> void
```

Clears CPU pressure history when the world/session or rendering policy
changes. This is visual-only: combat, server ticks and networking remain
completely outside adaptive full-pose budgeting.

### `adaptive_full_pose_budget_us`

```gdscript
static func adaptive_full_pose_budget_us(quality: int, frame_process_us: int, prefer_native: bool = true) -> int
```

A predictable native/stock-Godot CPU pressure controller. This only
adjusts the *optional* full-IK work-unit microsecond allowance; the
existing cap_full_pose_cost() still ranks actors by distance and prior
full-IK ownership and never reduces separately prioritized combat poses.
It consumes the most recently reported Godot Performance.TIME_PROCESS.

### `adaptive_pose_budget_snapshot`

```gdscript
static func adaptive_pose_budget_snapshot(quality: int) -> Dictionary
```

On-demand diagnostics; never constructed by the per-frame crowd path.

### `full_budget`

```gdscript
static func full_budget(quality: int) -> int
```

How many characters may run the full procedural stack (IK, look-at) per quality tier 0..3.

### `lod_tier`

```gdscript
static func lod_tier(distance: float) -> int
```

0 full rate + modifiers, 1 full rate no IK, 2 half rate, 3 quarter rate, 4 eighth rate.

### `lod_interval`

```gdscript
static func lod_interval(tier: int) -> float
```

Seconds between animation updates of a tier (0 = every frame).

### `assign_tiers`

```gdscript
static func assign_tiers(distances: Array, budget: int) -> PackedInt32Array
```

Assigns a tier to each character from its distance. Only the nearest `budget` characters may be tier 0;
the rest of the near crowd is demoted to tier 1. Returns tiers in the order of `distances`.

### `plan_crowd_tiers`

```gdscript
static func plan_crowd_tiers(distances: PackedFloat64Array, priority_flags: PackedByteArray, full_slots: int, priority_slots: int, prefer_native: bool = true, visible_flags: PackedByteArray = PackedByteArray(), retained_full_flags: PackedByteArray = PackedByteArray(), full_hysteresis: float = 0.0, retained_combat_flags: PackedByteArray = PackedByteArray(), combat_hysteresis: float = 0.0) -> PackedInt32Array
```

Batch-selects pose tiers. Native Cgame does bounded top-K on numeric
arrays; stock Godot uses an equivalent deterministic GDScript fallback.
visible_flags is optional for backward compatibility. When provided, off-screen
characters retain their distance tier but never outrank tier 2, and cannot
consume expensive procedural or combat-priority slots.
retained_full_flags adds a bounded distance discount for prior full-IK owners,
but only within the usual 22m / visible eligibility. A zero discount keeps
the original selection byte-for-byte compatible.

### `cap_full_pose_cost`

```gdscript
static func cap_full_pose_cost(tiers: PackedInt32Array, distances: PackedFloat64Array, retained_full_flags: PackedByteArray, full_pose_cost_us: PackedInt32Array, full_pose_budget_us: int, hysteresis: float = IK_RETENTION_HYSTERESIS_METRES, prefer_native: bool = true) -> PackedInt32Array
```

Cost-only second-stage admission. Call after the engine's distance,
visibility, sticky-IK and independently retained combat tiers are chosen.
This *never* promotes or demotes existing tier-1/2/3/4 poses.

### `cap_full_pose_cost_grouped`

```gdscript
static func cap_full_pose_cost_grouped(tiers: PackedInt32Array, distances: PackedFloat64Array, retained_full_flags: PackedByteArray, full_pose_cost_us: PackedInt32Array, group_ids: PackedByteArray, group_weights: PackedFloat64Array, full_pose_budget_us: int, hysteresis: float = IK_RETENTION_HYSTERESIS_METRES, prefer_native: bool = true) -> PackedInt32Array
```

Reserve a proportional share of the current measured IK allowance for
each active actor type, then redistribute unused shares in weighted
significance order. Uses ONLY the tier-0 actors that the existing planner
already selected. Never promotes tier-1/2/3/4 or slows combat locomotion.

### `smooth`

```gdscript
static func smooth(current: float, target: float, delta: float, rate: float) -> float
```

Exponential smoothing independent of frame rate.

### `smooth_rate`

```gdscript
static func smooth_rate(current: float, target: float, delta: float, max_rate: float = 4.0) -> float
```

Moves a playback rate toward its target at most `max_rate` per second (no pops when the speed bracket changes).

### `spring_step`

```gdscript
static func spring_step(x: float, v: float, target: float, stiffness: float, damping: float, delta: float) -> Array
```

One semi-implicit spring-damper step; returns [position, velocity].

### `lean_angles`

```gdscript
static func lean_angles(yaw_rate: float, speed: float) -> Vector2
```

Lean into a turn: [roll, pitch] radians for the spine. `yaw_rate` rad/s (positive = turning left), `speed` m/s.
Roll toward the inside of the turn, pitch forward with speed.

### `breath_angle`

```gdscript
static func breath_angle(t: float, moving_weight: float) -> float
```

Idle breathing: chest pitch in radians at time t, fading out while moving (`moving_weight` 0..1).

### `look_angles`

```gdscript
static func look_angles(body_basis: Basis, target_dir: Vector3, max_yaw: float, max_pitch: float) -> Vector2
```

Yaw/pitch (radians, clamped) needed to look along `target_dir` for a body whose basis is `body_basis`
(+Z forward, +Y up). Targets behind the body stay clamped at the limit, scaled down to zero when directly behind.

### `look_rotation`

```gdscript
static func look_rotation(body_basis: Basis, angles: Vector2) -> Quaternion
```

World-space rotation for a yaw/pitch look pair, expressed around the body frame.

### `lean_rotation`

```gdscript
static func lean_rotation(body_basis: Basis, roll: float, pitch: float) -> Quaternion
```

Rotation conjugated into world space: roll about the body forward axis, pitch about its lateral axis.

### `contact_weight`

```gdscript
static func contact_weight(height_above_plant: float, lift: float = 0.14) -> float
```

1 while a foot is on the ground, 0 once it lifted `lift` metres above its planted height (swing phase).

### `pelvis_offset`

```gdscript
static func pelvis_offset(left_delta: float, right_delta: float, limit: float = 0.35) -> float
```

Pelvis shift (<= 0 normally): the hips follow the lower foot target so neither leg overextends; clamped.

### `ground_normal`

```gdscript
static func ground_normal(h0: float, hx: float, hz: float, step: float) -> Vector3
```

Surface normal from a centre sample and two neighbours `step` metres along +X and +Z.

### `solve_knee`

```gdscript
static func solve_knee(a: Vector3, b: Vector3, c: Vector3, target: Vector3) -> Array
```

Analytic two-bone IK. Hip `a`, knee `b`, ankle `c`, desired ankle `target`. Returns [new_knee, new_ankle]; bone
lengths are kept, the knee bends toward its original side, unreachable targets are clamped to full extension.

### `is_upper_body_bone`

```gdscript
static func is_upper_body_bone(bone: String) -> bool
```

### `track_bone`

```gdscript
static func track_bone(path: NodePath) -> String
```

The bone a skeleton track path points at ("Armature/Skeleton3D:upperarm_l" -> "upperarm_l"); "" for non-bone paths.

### `upper_body_copy`

```gdscript
static func upper_body_copy(animation: Animation) -> Animation
```

Copy of `animation` that only drives upper-body bones (loop mode kept). Used by a second AnimationPlayer layered
over locomotion so a swing plays while the legs keep walking.

### `layerable`

```gdscript
static func layerable(animation_name: String, moving: bool, zombie: bool) -> bool
```

Whether an action clip should be layered over locomotion rather than replace it.

### `apply_crowd`

```gdscript
static func apply_crowd(models: Array, camera: Camera3D, quality: int, ground: Callable, pose_budget_us: int = -1) -> void
```

Once per frame over every live CharacterModel: distance LOD tiers within the crowd budget, terrain source for foot
IK, and a camera look-at for the closest few. `models` are CharacterModel nodes.

_1 private function(s) starting with `_` are not listed._
