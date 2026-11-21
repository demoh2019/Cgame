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
