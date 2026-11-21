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
