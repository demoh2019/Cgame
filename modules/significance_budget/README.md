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

## Stable significance for multiple observers

`select_world_priority_stable(positions, viewers, priorities, ids, retained_ids,
budget, max_distance, hysteresis=0.0)` ranks at most 16,384 world-space
candidates from up to 16 viewers, using strict priority tiers followed by
nearest-viewer distance, bounded retention hysteresis and stable positive ID.
It has deterministic ties, up to 128 slots, and a hard inclusive range that
retention cannot extend. The pure native algorithm performs O(N × (V + K))
work with a bounded top-K insertion rather than sorting the entire crowd.

The playable Albion After client uses it for its three nearest POI compass
markers; an 8m retention bonus reduces flickering as sites exchange order.
All marker urgency values are zero to preserve nearest-site semantics.
The game keeps the original entered-site and 650m exclusions and includes
stock Godot fallback parity tests. No measured performance claim is made.


## Albion After infected HUD integration

The on-screen infected health-bar overlay also uses the shared native
`select_world_priority_stable` selector, with the same stock-Godot fallback
as POI markers. Eligible enemies are filtered by squared distance and
projected screen bounds before native priority ranking. At most 32 bars
are drawn; no combat, enemy simulation or networking is affected.
Headless game regression tests cover two-viewer ranking, retention and
invalid input. No performance gains are claimed without runtime profiling.

## Niagara-style category-specific VFX range admission

`select_effects_visible_ranged(distances, priorities, categories, visible, category_caps, category_ranges, budget)` uses four finite inclusive visibility radii instead of a single shared global radius. Far-away dust cannot occupy slots intended for closer effects; critical milestones retain a long range. Priority, camera visibility preference, per-category quotas, total budget, deterministic tie ordering and fail-closed validation remain unchanged. This is opt-in and leaves the existing global-range API intact.

Albion After integrates the API in its real `effects.gd` burst queue, with separate quality-tier ranges and native/stock-Godot fallback parity. It affects visual-only effects, not server authority, damage, network state or audio. No unmeasured FPS improvements are claimed.

Unreal reference: https://dev.epicgames.com/documentation/en-us/unreal-engine/performance-budgeting-using-effect-types-in-niagara-for-unreal-engine

## Fair Niagara-style VFX category reservation (new)

`select_effects_visible_fair(distances, priorities, categories, visible,
category_caps, category_ranges, category_minimums, budget)` extends the
existing ranged-selector without changing it. The four minimums are soft
*per-category reservations*, not additional particle allowances.

The bounded native algorithm sorts at most four small top-K queues, then
does three deterministic phases:

1. **Emergency:** all eligible priority-3 cues are admitted first (until
   hard caps or the global frame budget fill).
2. **Diversity:** from remaining eligible candidates, fill each category's
   minimum as fairly as significance allows. Empty categories do not hold
   unused capacity.
3. **Fill:** use all remaining slots globally by priority, frustum
   visibility, distance and original index.

The entire batch is validated before selection. The sum of minimums cannot
exceed the total budget; each minimum must be no greater than its hard cap.
Maximum 16,384 candidates and 128 selection slots. The strict per-category
ranges, caps and frame budget never change. A zero-minimum array reproduces
`select_effects_visible_ranged` exactly. Time is O(N × K) and scratch
memory O(4 × K), with K ≤ 128; no scene access, RNG or per-frame state.

The **actual Albion After particle burst queue** uses this new method.
Quality-tier minimums reserve one or more hit/combat effects when there are
eligible requests; priority-3 events (boss kills, level-ups, urgent effects)
are unaffected. On older native engines and stock Godot, the game uses an
equivalent deterministic script algorithm. Tests verify native/fallback
parity, category scarcity, emergency priority and strict range boundaries.
This is cosmetic selection, not gameplay authority or a benchmarked FPS
change.

The idea builds on Unreal Niagara's per-Effect-Type budgeting and
significance features; this policy is a Cgame-specific soft quota and is
not a direct copy of the Unreal implementation:
https://dev.epicgames.com/documentation/en-us/unreal-engine/performance-budgeting-using-effect-types-in-niagara-for-unreal-engine

## Camera-cone significance for decorative world detail

`select_world_priority_stable_cone(positions, viewer, forward,
priorities, ids, retained_ids, budget, max_distance=1000,
hysteresis=0, half_angle_degrees=75, near_radius=3)` extends stable
world significance with **direction-aware cosmetic admission**:

```gdscript
var plan := SignificanceBudgetPlanner.new()
var selected := plan.select_world_priority_stable_cone(
    debris_positions, camera.global_position, -camera.global_basis.z,
    priority_tiers, stable_ids, previously_selected_ids,
    18, 26.0, 2.0, 75.0, 5.5)
```

- Rejects distant points behind the camera or outside a configurable
  inclusive **3D view cone**. Near-field points (within near_radius)
  remain eligible from all directions to prevent nearby detail holes
  during quick camera turns. The hard distance cap always applies.
- **Priority remains absolute** among eligible points. Retained IDs
  receive only the same within-tier distance hysteresis as the existing
  planner; low-priority decoration can never supersede a higher-priority
  candidate merely through retention.
- Full-cone half-angle=180 disables directional filtering and matches
  the one-viewer `select_world_priority_stable()` behavior. A 0-degree
  cone admits exactly aligned forward points plus the near-field.
- Up to 16,384 finite positions, matching priority/unique positive
  stable IDs, up to 128 prior IDs, and 0–128 selected indices. Camera
  vectors must be finite, forward nonzero; half-angle 0–180 degrees,
  max distance 0–1e6 and near radius 0–max distance. Invalid requests
  return empty atomically. No state, physics, scene edits or RNG.
- A fast O(N) validation/admission pass reuses the original bounded
  O(N × K) stable top-K selector, avoiding a full-world sort.
  This is a **cosmetic scheduling/cone heuristic**, not the renderer's
  actual frustum-plane test or GPU occlusion culling.

the removed Days After prototype (`debris_lod.gd`, in git history) now uses this API for 96 small
ruin fragments, with a strict 18-fragment presentation budget.
Camera direction updates which details are considered while the 5.5m
near field keeps close items from disappearing behind the camera.
Stock Godot runs a matching GDScript implementation. The gameplay
smoke turns the camera 180 degrees and asserts native/fallback parity,
full-distance cutoff, view-cone eligibility and restoration.

Reference: [Unreal Engine visibility and occlusion culling](https://dev.epicgames.com/documentation/en-us/unreal-engine/visibility-and-occlusion-culling-in-unreal-engine).

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
- Albion After uses the fair variant in the **real** pooled
  `Effects.flush_bursts()` path. Quality-tier particle budgets are
  96 / 160 / 256 / 384 (Performance to Ultra) in addition to existing
  scene-slot caps. The script fallback works in official Godot and older
  Cgame engines.
- `last_fx_budget_stats` reports `planned_particles` and `particle_budget`.
  These numbers measure admitted recipe particle counts, **not measured CPU
  time, actual pool allocation, GPU overdraw or frame rate**.

A particle budget prevents an overload of many individually affordable bursts
from producing an unbounded amount of cosmetic particle work in one frame.
It never modifies health, loot, damage, audio or multiplayer authority.
Validated by C++ doctests and `game/tests/test_fx_scalability_budget.gd`;
runtime FPS benefits should be benchmarked on representative hardware.

Unreal reference: https://dev.epicgames.com/documentation/en-us/unreal-engine/performance-budgeting-using-effect-types-in-niagara-for-unreal-engine

`select_effects_visible_fair_costed(distances, priorities, categories, visible,
particle_costs, category_caps, category_ranges, category_minimums, budget,
particle_budget)` applies the particle budget **inside** the fair quota
selection (`select_effects_visible_fair`): priority-3 events first, then the
soft per-category minimums, then the remaining most significant effects, with
per-category ranges and caps unchanged. An effect that no longer fits the
residual particle work is skipped, so an expensive effect can neither exceed
the budget nor block cheaper feedback; as a consequence a category minimum is
only guaranteed while its effects are affordable. With a large enough particle
budget it returns exactly the plan of `select_effects_visible_fair`.
`Effects.flush_bursts()` uses it (native when present, otherwise the identical
`FxPolicy.select_visible_fair_costed_indices()` GDScript fallback); the older
`select_effects_visible_costed` keeps its flat-range semantics.
