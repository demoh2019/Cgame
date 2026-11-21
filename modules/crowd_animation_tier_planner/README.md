# Native CrowdAnimationTierPlanner

A bounded, data-only C++ planner for the existing Albion After crowd
animation LOD pipeline. The design follows *significance-driven* skeletal
animation budgeting (Unreal's Animation Budget Allocator) but does not copy
that subsystem and does not change Godot's AnimationMixer.

`plan_tiers(distances, priority_flags, full_budget, priority_budget)` returns
one integer tier per character, in original input order.

| Tier | Render-side behavior already implemented by CharacterModel |
| --- | --- |
| 0 | Full-rate animation with expensive procedural modifiers |
| 1 | Full-rate animation without procedural foot IK/head-look extras |
| 2 | Reduced rate (30 Hz) |
| 3 | Reduced rate (15 Hz) |
| 4 | Reduced rate (8 Hz) |

Thresholds: 22, 38, 60, 90 metres. Up to `full_budget` nearest actors
inside 22m are tier 0. Up to `priority_budget` flagged, visible combatants
inside 90m are at least tier 1 even if farther away. Combat importance does
**not** grant tier 0, so it cannot exceed the expensive procedural stack
budget. Ties are resolved by original input index to avoid flicker.

Native implementation uses two stable, bounded top-K queues, requiring
O(N * (full_budget + priority_budget)) work and O(full_budget +
priority_budget) temporary metadata, rather than sorting all N characters
each frame. The module is safe to call from the main thread: it creates
no Nodes, does not touch the SceneTree, never advances skeletons, and
does not access physics or networking.

## Visibility-aware animation budgeting

`plan_visible_tiers(distances, priority_flags, visible_flags, full_budget,
priority_budget)` applies the same stable bounded top-K selection as the
legacy API but reserves **expensive tier-0 procedural foot IK** and
**tier-1 combat-priority** slots for visible actors. A non-visible actor
runs at **tier 2 or slower**, retaining tier 3/4 at larger distances; no
animation is frozen and no game-authoritative simulation is touched.

In Albion After, `CharacterAnim.apply_crowd` derives visibility from
`Camera3D.is_position_in_frustum` and `model.is_visible_in_tree`.
Actors closer than 3 metres are conservatively considered visible
whenever their model is visible, avoiding false negatives near screen
edges. Visible combat telegraphs keep their own independently bounded
priority pool. The next camera update immediately reassigns available
animation slots.

Backward compatibility: existing `plan_tiers` results and signatures
are unchanged. Newer Cgame builds use native top-K for visibility masks;
older builds and stock Godot use a matching deterministic GDScript
fallback. The planner never makes its own frustum tests. It is not a
full time-measured Animation Budget Allocator or a GPU visibility test.

## Stable full-IK budget under camera movement

`plan_visible_tiers_stable(distances, priority_flags, visible_flags,
retained_full_flags, full_budget, priority_budget, hysteresis=1.5)` extends
the native visible-crowd planner with **explicit, caller-owned temporal
retention**. Actors that held one of the expensive procedural IK slots last
frame get up to 1.5m of ranking advantage against similarly close peers.
A substantially closer newcomer can still win. The existing <=22m gate
and camera-visibility mask apply **before** retention, so invisible or distant
old owners immediately relinquish their slot. Ties use original actor order;
combat-priority slots are ranked independently by actual distance.

Unlike a fixed hold timer, this is stateless and reproducible for identical
input arrays. Bounds: 16,384 actors, 256 slots, retention mask length equal to
distances, finite hysteresis 0..8m. Zero hysteresis or an all-zero retention
mask produces exactly the previous `plan_visible_tiers` outputs.
Invalid masks/arguments return an empty array, with no partial state.

Albion After stores only the previous full-IK yes/no bit on each actual
`CharacterModel`. New or recycled models reset that bit. Its per-frame
`apply_crowd` pass feeds camera visibility, the retained mask, and the new
native API, updating the hint only when the assigned tier changes. Stock
Godot and older Cgame engines execute an equivalent script fallback.
This is a *presentation* optimisation: no server tick, authoritative
combat, physics, networking, or mixer playback correctness is changed.

The approach follows Unreal's Animation Budget Allocator **state-change
throttling** idea, not Unreal's proprietary code:
https://dev.epicgames.com/documentation/unreal-engine/animation-budget-allocator-in-unreal-engine

## Measured CPU work-unit admission (independent of combat scheduling)

The additional native API
`cap_full_pose_cost(tiers, distances, retained_full_flags, full_pose_cost_us,
full_pose_budget_us, hysteresis=1.5)` is a pure-data **second-stage**
allocator. It can be applied after either `plan_visible_tiers_stable` or
`plan_visible_tiers_temporal`, preserving **both independent IK and
combat-pose retention budgets** already present in the engine.

Only existing **tier-0 full procedural IK** owners compete for this
predicted microsecond cap. They retain the deterministic previous-IK
distance bonus and original-index ties; predicted work that does not
fit demotes an owner to **tier 1** (full-rate animation, without optional
procedural extras). There is no cost-based change to the independently
selected full-rate combat queue, and actors outside the existing IK
winners never gain a new slot. A zero global time budget disables this
additional cap and exactly preserves the original tier array.

Each per-actor sample is an integer 0..100,000us; 0 means **unsampled**
and uses an initial 100us work-unit estimate, following the idea from
Unreal's Animation Budget Allocator. Maximum total budget is 1,000,000us;
invalid or mismatched requests fail atomically. At most 256 tier-0
winners are ranked. Actual work may exceed the estimate: the budget is
**soft**, not a hard real-time deadline.

Albion After's `character_anim_modifier.gd` measures its GDScript
SkeletonModifier3D full-pose execution with `Time.get_ticks_usec()`
and a bounded quarter-weight EWMA. The existing real
`CharacterAnim.apply_crowd` retains both combat and IK history,
performs the usual dual-retention tier selection, and then feeds
measured per-model costs to `cap_full_pose_cost`. Quality-specific
limits are Performance **0us** (no full-IK slots), Balanced **750us**,
High **1500us**, Ultra **2750us**. Older Cgame builds and stock Godot
use the same deterministic script fallback.

**Measurement boundary:** this samples the scripted procedural modifier
only. It excludes GPU skinning, native FootPlacementModifier3D, the
AnimationMixer and all other render/physics workloads. It is a
partial implementation of the work-unit budgeting idea, not a full
Unreal Animation Budget Allocator replacement. No measured FPS gain
is claimed without engine builds and gameplay profiling.

Unreal reference:
https://dev.epicgames.com/documentation/unreal-engine/animation-budget-allocator-in-unreal-engine

## Adaptive main-thread CPU pressure controller (feedback from the rendered game)

`CrowdAnimationBudgetGovernor` is a separate native `RefCounted`
controller that adjusts the **existing cost-based optional tier-0 IK
limit** in microseconds. Unlike the stateless tier planner, this one
maintains only tiny bounded CPU pressure counters; it does not own
Skeleton3D nodes, mixers, combat poses, callbacks or game logic.

- Call `configure(max_budget_us, target_process_us=12500)` on quality
  changes. Max budget is in 0..100000us, process target 1000..100000us.
- Once each completed render frame, report the main-thread **CPU process
  duration** in microseconds to `observe_process_time(duration_us)`,
  which returns the adjusted optional full-pose allowance.
- Quarter-weight integer EWMA smooths the reported process-time signal.
  Two consecutive 12-frame windows above 95% of the process target
  reduce the existing allowance by ~25% (floor 25% of max). Three
  consecutive windows below 70% recover 1/8 of the maximum per step.
  Neutral pressure resets both streak counters and leaves budget intact.
- Zero samples are treated as unknown; negative/over-1-second samples
  return -1 without changing pressure, and invalid configurations fail
  atomically. An unchanged `configure` call retains evidence; quality
  changes, `reset()`, or re-enabling after a pause clear old evidence.
  Use `get_smoothed_process_us()`, `get_pressure_percent()`,
  `get_current_budget_us()` and `get_frames_observed()` for diagnosis.
- A zero maximum (Performance quality) continues to grant zero full-IK
  slots via the existing slot policy. This is a **soft** work-unit cap,
  not preemptive control of animation or an FPS guarantee.

Albion After integrates this in the actual
`entity_view.gd::_process` character pass using
`Performance.get_monitor(Performance.TIME_PROCESS)`, **not**
unrelated GPU-limited total frame delta. The real
`CharacterAnim.apply_crowd` continues to use the same visibility-aware
tier planner, independent full-IK/combat retention and measured
`cap_full_pose_cost` API; only its *optional IK microsecond allowance*
is dynamically reduced on sustained CPU frame pressure. Quality
maximums remain **0/750/1500/2750us**. Frame-pressure target is
12500us. When no native class is available, deterministic GDScript
fallback runs the identical algorithm; its explicit
`reset_adaptive_pose_budget()` is invoked when a new entity view
enters the tree. Developer diagnostics are available via
`CharacterAnim.adaptive_pose_budget_snapshot(quality)`.

**Limitations:** CPU process time includes many client systems and can
fluctuate for reasons unrelated to IK. The controller intentionally
adapts only optional procedural IK rather than slowing authoritative
combat animation. Reported pose costs are estimates from previously
measured modifiers. No actual CPU/GPU benchmark or FPS improvement is
claimed until native CI and in-game profiling complete.

Unreal comparison:
https://dev.epicgames.com/documentation/unreal-engine/animation-budget-allocator-in-unreal-engine

## Group-fair measured IK CPU allocation (Unreal Significance Manager pattern)

A significant remaining gap was that `cap_full_pose_cost` always
consumed the optional IK CPU allowance nearest-first, even when a dense
group of ordinary infected monopolized the budget ahead of nearby
players or elite enemies. Unreal Engine's Significance Manager
explicitly supports different budgets by actor category; this is an
independent, small data-only counterpart in Cgame.

`cap_full_pose_cost_grouped(tiers, distances, retained_full_flags,
full_pose_cost_us, group_ids, group_weights, full_pose_budget_us,
hysteresis=1.5)` is a **second-stage cost admission** applied to
existing tier-0 actors from the visibility-aware/temporal planner.
Up to four groups (0..3) compete for a shared estimated CPU allowance.
Four caller-selected finite weights (0.25..8) reserve proportional
microseconds **only for groups that have eligible tier-0 actors**.

1. The first pass admits affordable tier-0 winners within each group's
   weighted reservation. Inside each group, nearest retained actors
   retain deterministic preference and index-stable ties.
2. Remaining unspent quota and integer-rounding remainders are shared
   in a second pass across remaining eligible tier-0 winners, ranked
   by `max(0, distance - retained_hysteresis) / group_weight`.
3. Unadmitted owners become **tier 1**, retaining full-rate base
   locomotion and combat. Existing tier-1/2/3/4 poses never change.
   This function never promotes outside the original IK slot winners.

One active group gets the full original budget; zero CPU allowance
disables the additional cost gate entirely. A missing cost sample uses
a 100us estimate. Up to 16,384 actors and 256 full IK owners are
supported; group identifiers 0..3 and arrays are validated atomically.
Weighted shares are **soft**: a group can fail to fit a single
expensive work unit within its share, and leftover time is then
redistributed. This is not a minimum number of animations per cohort,
nor a guarantee about actual CPU frame time.

Albion After passes the measured combined scripted/native IK work-unit
costs and the already adaptive `CrowdAnimationBudgetGovernor`
allowance. The live `CharacterModel.setup` assigns group 0 to
players and 1 to normal infected. `entity_view.gd` elevates elite
infected and raid bosses to group 2. Group 3 remains available for
future cinematic/quest actors. Weights default to
`[3.0, 1.0, 2.0, 2.0]`. Pooled model reconfiguration resets its
category, so old occupants cannot steal another group's reservation.

Both custom Cgame and stock Godot use equivalent deterministic
numeric algorithms, selected by optional ClassDB availability.
Combat-priority full-rate slots and authoritative AI/network/physics
ticks remain unchanged. No measured FPS gain is claimed until native
CI/build and real gameplay profiling verify the implementation.

References:
- https://dev.epicgames.com/documentation/unreal-engine/significance-manager-in-unreal-engine
- https://dev.epicgames.com/documentation/unreal-engine/animation-budget-allocator-in-unreal-engine

## Safety and portability

- At most 16,384 actors; priority flags must match distances 1:1.
- Budgets range from 0 through 256.
- Every distance must be finite and nonnegative.
- An invalid request returns an empty result, without partially applying
  any animation state.
- Albion After automatically selects the native implementation through
  `ClassDB` where available; stock Godot uses an equivalent deterministic
  GDScript implementation.
- Both paths preserve the existing `CharacterAnim.apply_crowd` contract
  and `AnimationLODController` ownership of actual mixer updates.

This is a **tier-selection** optimisation, not a GPU renderer, full
Animation Budget Allocator, or an FPS claim. Benchmark on the native
Godot build before asserting any speedup.

## Tests

- C++: `tests/scene/test_crowd_animation_tier_planner.cpp`
- Godot runtime: `game/tests/test_crowd_animation_tier_planner.gd`
- Source/numeric contracts:
  `tests/scene/test_crowd_animation_tier_contract.py`

A compatible Cgame editor can run:

```sh
scons platform=linuxbsd target=editor tests=yes module_crowd_animation_tier_planner_enabled=yes
bin/godot.linuxbsd.editor.x86_64 --headless --test --test-case="*[CrowdAnimationTierPlanner]*"
bin/godot.linuxbsd.editor.x86_64 --headless --path game --script res://tests/run_all.gd
```

## Stateful-in-input LOD hysteresis (Unreal / Unity-inspired)

`plan_tiers_stable(distances, priority_flags, previous_tiers, full_budget,
priority_budget, hysteresis_meters)` is a data-only companion to
`plan_tiers`. It uses the **previous output for the same actors** to introduce
a symmetric 0–4 m dead band around each 22/38/60/90 m distance boundary.
A camera moving a few centimetres back and forth around a threshold will
not toggle a crowd's animation rate every frame.

The native planner retains its absolute hard full-pose and combat-slot
budgets. Previously chosen tier-0 and tier-1 combat characters get a small
bounded distance preference to reduce churn, but never reserve a slot when
their corresponding flags are absent. Multi-tier teleports are immediate.
`hysteresis_meters=0` yields the old algorithm's result. Invalid size,
distance, previous-tier, budget and hysteresis inputs fail atomically.

Albion After reads `CharacterModel._lod_tier` once for each existing model
and sends those aligned tiers to the native planner, or runs the equivalent
GDScript fallback on official Godot. The engine holds no actor IDs, Nodes,
world coordinates or gameplay state, and neither path affects authoritative
combat or networking. All expensive procedural animation remains budgeted.

Design inspiration: Unreal Animation Budget Allocator (significance-based
skeleton work) and Unity LOD Group transition zones. This **does not**
implement crossfading, GPU optimization or Unreal's complete allocator.
## Independent combat-pose retention

The IK-only `plan_visible_tiers_stable` API remains unchanged. The new
`plan_visible_tiers_temporal(distances, priority_flags, visible_flags,
retained_full_flags, retained_priority_flags, full_budget, priority_budget,
full_hysteresis, priority_hysteresis)` adds **independent temporal significance
for combat-critical full-rate poses**, inspired by Unreal Engine's Animation
Budget Allocator. The planner accepts separate previous-frame ownership masks,
then gives each eligible owner a small *ranking* distance discount, not a
longer range or another budget slot.

- Full IK retains its existing 0–8m bonus and strict visible / 22m gate.
- Combat pose priority has its own 0–4m bonus, strict visibility / 90m
  gate, and unchanged `priority_budget` cap.
- Different actors may retain IK and combat slots. Ties are deterministic
  and the native implementation uses bounded top-K queues.
- Invalid, mismatched or non-finite inputs fail atomically to an empty batch;
  priority retention 0 preserves the exact existing IK-only output.

Albion After now stores a per-character `aa_combat_pose_retained` hint,
separate from its pre-existing `aa_full_ik_retained` hint. Only a visible,
combat-flagged character promoted from the naturally slower tier (distance
>=38m) may carry the priority hint to the next frame. Pooled models reset
both flags. Stock Godot and older Cgame builds fall back to matching
GDScript ranking without losing the new behavior. This never modifies
damage, server AI, physics, or networking.

The engine exposes an *additional* method rather than changing the existing
stable planner's signature, so scripts compiled against prior Cgame releases
continue to work. This is stability of presentation scheduling, **not**
a measured FPS improvement or a full Unreal animation framework.
