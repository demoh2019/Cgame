# Cgame SignificanceBudgetPlanner

A native, pure-data **significance budget selector** inspired by Unreal Engine Significance Manager, adapted to the Cgame custom Godot fork. Useful for deciding which UI markers, VFX emitters, cosmetic audio or nonauthoritative character updates receive scarce per-frame work.

- **select_top(distances, priorities, budget)**: deterministic priority-first nearest-K. Priority levels 0..3, then distance, then stable original index.
- **select_world(positions, viewers, priorities, budget, max_distance)**: distance to nearest of up to 16 observers, with an inclusive max range. Accepts up to 16,384 candidate positions.
- Atomic validation: NaN, infinite, negative distances, invalid priorities, arrays of different lengths, budgets >128, invalid viewers/world positions fail closed.
- Bounded insertion with **O(N × K)** comparisons and **O(K)** metadata; no full-crowd sort; no RNG, scene-tree work, physics calls or global mutable state.
- Returns ordered indices. **It does not automatically cull actors** and never makes authoritative simulation decisions.

## Immediate Albion After integration

`game/scripts/client/world_overlay.gd` now caps overlapping zombie health bars at 32 after the existing 45m and screen-position visibility checks. Critical raid bosses (priority 3), elite infected (2), attacking infected (1) and regular infected (0) compete for the slots in that order, nearest first. Damage calculations, spawning, actual AI, loot, network and visibility of 3D characters remain untouched. Stock Godot and older Cgame builds use the exact same significance ordering in GDScript.

Native doctests live under `tests/`, and `game/tests/test_world_overlay_significance.gd` checks native/fallback parity and budget limits. Real FPS savings require runtime profiling; no benchmark improvement is claimed.

Based on Unreal's significance concepts: https://dev.epicgames.com/documentation/en-us/unreal-engine/significance-manager-in-unreal-engine

## Stable significance for persistent visual budgets

`select_top_stable(distances, ids, retained_ids, budget, max_distance, hysteresis)`
selects a bounded top-K in native C++ with a temporal retention bonus. This
reduces flicker from a moving camera near a slot threshold without retaining
out-of-range objects. IDs are stable across changing candidate order; invalid
or duplicate IDs fail closed. Albion After uses this to select dungeon torches
from the global light pool, while preserving a same-order GDScript fallback
for stock Godot. Shadow-casting budgets remain independent and capped.

## Native Niagara-inspired Effect Type budgets

`select_effects(distances, priorities, categories, category_caps, budget,
max_distance)` ranks visual-only effect descriptors by priority (3 first),
then camera distance, then stable source order. Four independent groups,
each capped at 0..128, compete under a shared <=128 effect budget.
The implementation is pure C++, O(N*K) with O(4*K) scratch, validating
all inputs before returning an output. Category caps prevent a burst of
dust or ordinary hit particles from consuming all presentation slots.

Albion After uses it via `fx_scalability_policy.gd` and `effects.gd`.
These only control local presentation and never affect gameplay damage,
network authority, event delivery, audio or inventory. The script fallback
implements identical ordering on stock Godot.

Reference: Unreal Engine Niagara Effect Types and scalability:
https://dev.epicgames.com/documentation/en-us/unreal-engine/performance-budgeting-using-effect-types-in-niagara-for-unreal-engine


## Priority-aware temporal significance

`select_top_priority_stable(distances, priorities, ids, retained_ids, budget, max_distance, hysteresis=0.0)` ranks **strict 0–3 urgency before** a within-tier distance discount for last-frame retained IDs. Tie breaks are deterministic by actual distance then stable positive ID. The hard range is never extended by the discount. Invalid IDs/arrays fail closed. Ranked top K remains O(N × K) with O(K) ranking scratch and O(N) ID validation. This extends the engine toward Unreal Significance Manager's flexible per-object prioritization.

Albion After uses it for its 32 visible infected health bars. Retention reduces HUD churn as same-priority zombies move and never lets a previously visible ordinary enemy obscure a higher-priority boss or elite. Stock Godot follows the same algorithm. No server AI, combat, replication or actual 3D actor culling is changed.

Unreal Significance Manager: https://dev.epicgames.com/documentation/en-us/unreal-engine/significance-manager-in-unreal-engine

## Frustum-prioritized presentation (on-screen VFX)

`select_effects_visible(distances, priorities, categories, visible, category_caps,
budget, max_distance)` extends the Niagara-inspired type-budget planner with a
0/1 camera-frustum hint. Priority tier remains the primary key; only effects
of equal priority prefer on-screen emitters, then distance and stable input
order. Per-category quotas, hard range, bounds and fail-closed validation are
preserved. This is *frustum admission*, not GPU occlusion culling.

Albion After's `effects.gd` now feeds `Camera3D.is_position_in_frustum()`
for each pending cosmetic burst and uses the native selector when available.
`fx_scalability_policy.gd` has matching pure GDScript behavior on stock
Godot or older Cgame binaries. Gameplay, audio, server state and networking
are not affected. The user-visible impact requires profiling in a running
scene; no FPS improvement is claimed.

## Dual-budget Niagara-style admission (particle work)

`select_effects_visible_costed(distances, priorities, categories, visible,
particle_costs, category_caps, budget, max_distance, particle_budget)` applies
the existing global effect-slot and per-type caps **plus a hard sum of the
requested particles**. The method retains priority > on-screen > distance >
input index ordering. When the next effect is too expensive, it skips that
candidate and may fill spare capacity with cheaper effects. A hard radius is
always enforced; all inputs are checked before any selection is returned.

- At most 16,384 candidates, 128 effect slots, four effect categories and
  65,536 particle work units. Each effect must cost 1 to 4,096 units.
- Native C++ keeps work bounded to O(N × selected slots) and O(N) bytes of
  temporary selection flags. No global RNG, GPU query or scene-tree mutation.
- Albion After uses it in the **real** pooled `Effects.flush_bursts()` path.
  Quality-tier particle budgets are 96 / 160 / 256 / 384 (Performance to Ultra)
  in addition to existing scene-slot caps. The script fallback works in
  official Godot and older Cgame engines.
- `last_fx_budget_stats` reports `planned_particles` and `particle_budget`.
  These numbers measure admitted recipe particle counts, **not measured CPU
  time, actual pool allocation, GPU overdraw or frame rate**.

A particle budget prevents an overload of many individually affordable bursts
from producing an unbounded amount of cosmetic particle work in one frame.
It never modifies health, loot, damage, audio or multiplayer authority.
Validated by C++ doctests and `game/tests/test_fx_scalability_budget.gd`;
runtime FPS benefits should be benchmarked on representative hardware.

Unreal reference: https://dev.epicgames.com/documentation/en-us/unreal-engine/performance-budgeting-using-effect-types-in-niagara-for-unreal-engine
