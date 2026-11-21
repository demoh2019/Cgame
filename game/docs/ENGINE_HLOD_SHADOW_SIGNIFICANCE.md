# Native HLOD shadow-caster significance and Albion After integration

Unreal Engine World Partition's HLOD system uses spatial grouping to
reduce the rendering cost of distant worlds. Cgame already groups meshes
with MultiMesh and culls distant instances, but each group formerly
decided independently whether to draw expensive solar shadows.
This extension adds a **bounded significance selection** for those
existing groups without generating any new proxy meshes.

Reference: https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition-hierarchical-level-of-detail-in-unreal-engine

## Native engine

`SignificanceBudgetPlanner.select_shadow_casters(bounds_min, bounds_max,
roles, current, camera, role_radii, budget=16, hysteresis=5.0)`

Input arrays use the same source-index order:
- `bounds_min/max`: world-space AABB corners as PackedVector3Array.
- `roles`: 0 bush, 1 tree, 2 structure, 3 disabled/unknown.
- `current`: 0 or 1, whether the corresponding group currently casts.
- `camera`: current viewer position. Only **X/Z bounds distance** matters.
- `role_radii`: three finite nonnegative distances in bush/tree/structure
  order. A zero radius disables the role.
- `budget`: at most 128 groups; up to 16,384 candidates per call.

The native selector returns original candidate indices sorted by
descending role importance (structures, trees, bushes), then
distance-to-nearest-AABB-boundary with an active-state retention bonus,
then raw distance, then source index. A caster becomes eligible within
`radius - hysteresis` and stays eligible until `radius + hysteresis`.
It rejects mismatched, nonfinite, inverted or too-large AABBs and
invalid roles, flags or budgets atomically with no partial plan.

Memory and sorting work are bounded by O(budget) extra storage and
O(candidates * budget) comparisons. The selector never changes scene
objects, physics, world streaming, replication or server authority.

## Albion After

`ShadowBudget.select_shadow_casters()` dispatches to native when
available; otherwise its GDScript fallback uses the same formula and
stable ordering. Every streamed `ChunkView` converts existing GPU
MultiMesh caster bounds into world coordinates, asks the planner for a
bounded set, and toggles sun-shadow casting only when needed.
It does not rebuild geometry or modify collision/loot.

Per-chunk target caps for Performance/Balanced/High/Ultra:
**0 / 8 / 16 / 24** visible solar shadow groups. These are *additional*
to the existing role-radius policies and 5 m hysteresis, not replacements.
The existing 0.5 s refresh interval and camera motion gate are preserved.
Already active shadow groups can be culled by the hard cap; no
gameplay-critical visibility or interaction is affected.

## Tests and CI

- C++: `modules/significance_budget/tests/test_significance_budget_planner.h`.
- Game native/fallback parity: `game/tests/test_hlod_shadow_casters.gd`.
- Standalone runner: `game/tests/run_hlod_shadow_casters.gd`.
- Workflow: `.github/workflows/native-hlod-shadow-casters.yml`.
- Registered in `game/tests/run_all.gd`.

**Performance caveat:** the cap bounds the number of shadow-casting
MultiMesh groups *per chunk*, not a global number across streamed
chunks. Actual GPU frame-time improvement must be measured separately.
