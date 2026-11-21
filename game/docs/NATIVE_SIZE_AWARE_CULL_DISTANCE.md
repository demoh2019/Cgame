# Native size-aware draw distance for Albion After

Reference: [Unreal Engine Cull Distance Volumes](https://dev.epicgames.com/documentation/en-us/unreal-engine/cull-distance-volumes-in-unreal-engine).
Unreal's Cull Distance Pairs map an object's longest bounds dimension to
draw distance without interpolation, and keep each Actor's authored max range.

## Engine

The Cgame native module `modules/cull_distance_policy` adds:

`CullDistanceProfile3D.get_cull_distance(bounds: AABB,
sizes: PackedFloat32Array, ranges: PackedFloat32Array,
authored_distance: float = 0.0) -> float`

- Uses **the longest AABB dimension** (not the diagonal or center distance).
- Finds the nearest size among 1–128 unordered pairs; **no interpolation**.
  Equidistant pairs choose the smallest **positive** range; zero means no
  extra culling and is not treated as the most aggressive distance.
- A positive authored maximum always caps the returned distance. If the chosen
  pair has range zero, the authored limit survives. Both zero = unlimited.
- Bounds positions must be finite within +/-10 million, sizes and ranges
  finite within 0–1 million, and bounds dimensions finite, nonnegative and
  at most 1 million. All validation occurs **before** selecting a range.
- The native method returns **-1** on invalid input (distinct from zero
  meaning unlimited). It is **pure**: no renderer, scene nodes, global state,
  background work or allocations that depend on the number of instances.

The feature is a reusable size-profile **policy**, not a Godot
Cull Distance Volume Node3D/editor implementation, and it does not perform
visibility tests itself.

## Albion After

`SceneryLod.apply` runs the new size-based profile only for
non-gameplay `decor:*` MultiMesh batches that have a valid nonempty
`custom_aabb` and a positive author draw limit.

For performance/balanced/high/ultra tiers, the underlying authored distance
is still `base_distance * decor_scale`. The profile additionally applies
size-distance pairs in **metres**:

| Longest local cluster extent (m) | Nominal range before tier scale (m) |
|---|---|
| nearest to 1 | 45 |
| nearest to 4 | 75 |
| nearest to 10 | 105 |
| nearest to 24 | 160 |
| nearest to 64 | 0 (no additional culling) |

Cgame and the stock Godot fallback both use the exact nearest-size policy.
The ranges are multiplied by the existing quality `decor_scale`
(Performance 0.55, Balanced 0.80, High 1.0, Ultra 1.2).
The original artist-authored draw range remains a hard upper bound.

Groups with no custom bounds remain unchanged. Foliage trees/bushes, resources,
collision, interactive objects, gameplay spawns, multiplayer replication,
big landmarks and terrain receive **no new distance restrictions**.
Even small cosmetic batches have the existing engine range margin, helping
avoid harsh visibility transitions. The profile runs during existing scenery
adoption or quality changes; no per-frame per-instance work is introduced.

## Verification

Native C++ doctests: `modules/cull_distance_policy/tests/test_cull_distance_profile_3d.h`

Existing full game suite: `game/tests/test_scenery_lod.gd`

Focused runner: `game/tests/run_cull_distance_policy.gd`

CI workflow: `.github/workflows/native-cull-distance-policy.yml`

Native/fallback deterministic parity checks cover 64 seeded AABBs; game tests
also check authored limits, zero/infinite ranges, tie-breaking, unsafe data,
quality changes, and preservation of landmark/tree culling.

**Do not claim an FPS or GPU gain** until hardware benchmarks measure actual
costs: a smaller visibility radius is intended to reduce draw calls, not a
guaranteed frame-time improvement. Headless tests verify policy, not rendering.
