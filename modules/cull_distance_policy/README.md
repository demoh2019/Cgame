# Cgame cached Cull Distance Profiles

Inspired by Unreal Engine [Cull Distance Volumes](https://dev.epicgames.com/documentation/unreal-engine/cull-distance-volumes-in-unreal-engine?lang=en-US): choose a cull limit by the **nearest longest AABB side**, with no interpolation. Tied sizes prefer the smallest positive distance; zero means "no additional cull", and an authored positive max draw distance is never increased.

The existing stateless `get_cull_distance(bounds, sizes, ranges, authored_distance)` remains available and unchanged to callers. For streamed worlds that apply the *same* size/range pairs to many visual instances, **configure once and resolve many times**:

```gdscript
var profile = CullDistanceProfile3D.new()
assert(profile.configure(
    PackedFloat32Array([1.0, 4.0, 10.0, 24.0, 64.0]),
    PackedFloat32Array([24.75, 41.25, 57.75, 88.0, 0.0])))
var end_distance = profile.get_cached_cull_distance(instance.custom_aabb, 80.0)
if end_distance >= 0.0:
    instance.visibility_range_end = end_distance
```

The C++ `configure` method validates all pairs atomically (1–128, finite, nonnegative, values ≤1,000,000). Invalid input leaves the previous profile usable. `get_cached_cull_distance` reuses stored, copy-on-write packed arrays and validates only per-instance AABB and authored cap. Unconfigured or invalid calls return -1, distinct from the valid unlimited range 0. `clear_profile()` and `get_pair_count()` provide explicit lifecycle and diagnostics.

## Real Albion After usage

`game/scripts/client/scenery_lod.gd` creates **one configured native profile per graphics quality tier**, reused for every decor MultiMesh, instead of allocating two packed arrays and validating 5 pairs on every `SceneryLod.apply`. The stock-Godot/older-binary fallback reuses the same four quality-scaled packed arrays and the legacy resolver. Decorative visual culling is applied only if a valid profile result is returned. Landmark visibility, terrain collisions, foliage silhouettes, gameplay resources, server logic, networking, and authored distance caps remain unchanged.

Expected improvement is lower per-instance **CPU setup overhead** when streaming/reconfiguring many visual batches; this is not an FPS benchmark claim. The per-instance size resolution still scans at most 128 configured pairs, and no render passes or GPU readbacks are added.

## Verification

Native C++ doctests: `modules/cull_distance_policy/tests/test_cull_distance_profile_3d.h`.

Headless game tests: `game/tests/run_cull_distance_policy.gd` (`test_scenery_lod.gd`).

Source contracts: `python3 -m unittest tests/scene/test_cull_distance_cached_contract.py -v`.

Dedicated GitHub Actions workflow: `.github/workflows/native-cull-distance-policy.yml`.

Building Cgame and running both native/game tests is required before considering the change runtime-verified.

## Bounded bulk draw-distance selection (quality-switch hot path)

`get_cached_cull_distances(positions, sizes, authored_distances)` computes
up to **4,096** independent draw distances per native call using the
already-configured profile. The three packed arrays describe each
`AABB(position, size)` and its authored max draw distance; every index is
preserved. A malformed input anywhere (including the last row), an
unconfigured profile, mismatched array sizes, or more than 4096 objects
returns an **empty** result, so no partial output is applied. The operation
does not touch `SceneTree`, GPU buffers, game entities or network state.

`SceneryLod.apply_many` now uses this when **Albion After graphics quality is
changed**: it gathers eligible streamed decorative `MultiMeshInstance3D`
batches, groups them by the chosen quality preset in bounded chunks and
updates visibility margins and LOD bias while preserving the previous
scalar result. A quality switch with thousands of decorative batches no
longer requires one GDScript-to-C++ call for each. The normal
`SceneryLod.apply` path still handles individually streamed/new batches,
and stock Godot/older custom engines use a deterministic pure-script
fallback. Invalid/unset custom AABBs keep their previously authored end
distance, while landmark and gameplay geometry retain the prior behavior.

The API keeps the existing nearest-longest-dimension, no-interpolation
selection and authored cap semantics, inspired by
[Unreal Cull Distance Volumes](https://dev.epicgames.com/documentation/unreal-engine/cull-distance-volumes-in-unreal-engine?lang=en-US).
This reduces expected cross-language dispatch overhead; it is **not a
measured frame-time or FPS gain**. Run the native doctests and the
`game/tests/run_cull_distance_policy.gd` headless regression first.
