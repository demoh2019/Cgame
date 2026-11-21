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

## Measured full-pose CPU budget (Unreal-style work-unit pressure)

`plan_visible_tiers_costed(distances, priority_flags, visible_flags,
retained_full_flags, full_pose_cost_us, full_budget, priority_budget,
full_pose_budget_us, hysteresis=1.5)` adds a **second soft admission cap**
to the existing stable/visible tier-0 IK pool. The existing distance,
visibility and retention rules choose up to `full_budget` winners first;
then each accepted full-pose cost estimate must fit the remaining
microsecond allowance. Over-budget winners are demoted to tier 1, still
playing full-rate locomotion and combat. This does not refill vacated IK
slots with actors outside the original winning set: it avoids a second
full-crowd ranking and preserves the established order of significance.

An unknown actor reports cost 0 and uses an initial estimate of **100us**.
Samples must be finite integers 0–100,000us, total CPU budget 0–1,000,000us.
Budget 0 disables this extra gate, reproducing the existing stable API.
Input errors fail atomically; neither native nor fallback stores scene
references or runs callbacks. Predicted cost **is not a hard deadline**:
actual pose time can fluctuate, and slow frame times can still occur.

In Albion After, `character_anim_modifier.gd` measures its *actual
GDScript procedural modifier pass* with `Time.get_ticks_usec()` when the
full-pose layer is active, and retains an integer 1/4 EWMA estimate for
the next frame. The client passes one estimate per actor to the engine
and scales the soft optional script-pose CPU cap by visual quality:
Performance **0us** (tier-0 slots already disabled), Balanced **750us**,
High **1500us**, Ultra **2750us**. Newly spawned actors use the 100us
default until a full-pose update can be measured. Stock Godot and older
Cgame builds use an equivalent deterministic GDScript fallback.

**Measurement boundary:** the sample covers *only the scripted
SkeletonModifier3D full-pose pass*. It does NOT measure GPU skinning,
native FootPlacementModifier3D, AnimationMixer, server logic, or all
skeleton update work. This is a partial step toward Unreal's
Animation Budget Allocator, not a complete replacement. No actual
FPS improvement is claimed without profiling a running game.

Unreal documentation:
https://dev.epicgames.com/documentation/unreal-engine/animation-budget-allocator-in-unreal-engine

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
