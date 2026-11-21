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
