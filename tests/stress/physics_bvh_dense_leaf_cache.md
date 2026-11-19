# Dense BVH ray-leaf entry cache

## Motivation

Cgame's BVH ray traversal visits the nearest AABB proxy first for leaves
containing at least 16 objects. Until this change it ran a full slab
intersection against **every AABB twice**: first to select the nearest
proxy, then again while processing the remaining items.

Box2D uses a clipped ray fraction in its dynamic-tree callback and Jolt
uses an early-out fraction in closest-hit collectors. Cgame already
employs the same callback principle; this change reuses the AABB entry
fractions calculated for nearest-first scheduling.

## Implementation

`core/math/bvh_cull.inc::_cast_segment_iterative()` caches the entry
fraction for each proxy of a dense leaf in a fixed-size stack array
`real_t dense_entry[MAX_ITEMS]`.

- Only one ray/box slab check is performed per dense-leaf proxy during
  the initial ordering scan.
- Missed proxies are assigned `Math::INF`. Matching proxies store the
  original-ray entry, which is compared against the current closest-hit
  fraction when the exact callback can clip the ray.
- A lower collision fraction never invalidates the cached *entry* since
  all fractions use the unchanged original ray.
- Leaves with fewer than 16 items keep their original single-pass
  no-cache path. User-cull filters, both BVH trees, collision masks,
  early-out at zero, and original candidate scheduling are preserved.
- No persistent storage or new allocations **per collider**. The
  temporary array can increase stack use by up to `sizeof(real_t) *
  MAX_ITEMS` for a query frame; the built-in GodotPhysics BVH uses
  `MAX_ITEMS=128`.

No code is imported from another engine.

## Validation

- Native tests: `tests/core/math/test_bvh_dense_leaf_cache.cpp`
  (2D/3D, two BVH trees, 64 shapes, eligible/ineligible narrowphase
  candidates, masked queries, clipping correctness).
- Existing `test_bvh_dense_leaf.cpp` covers closest-first ordering,
  skipping the nearest shape, reverse casting, and the small-leaf path.
- Headless `physics_bvh_dense_leaf_cache_regression.gd` creates 96
  2D and 96 3D static colliders, queries both dimensions repeatedly,
  and verifies closest, excluded, reverse and masked results.

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path tests/stress \
  --script res://physics_bvh_dense_leaf_cache_regression.gd
```

The separate Python reference model simulated **8000 random rays** in
2D/3D with 80 proxies per leaf and candidate filtering. It matched the
nearest hit on every ray. The modeled count was 1,183,125 slab tests
before vs 640,000 after, about 45.9% fewer. **This is not an actual
Cgame benchmark or an FPS increase.**

Build the engine with `tests=yes` and run native `[BVH]` cases,
then compare real CPU and RSS in both dense-leaf and shallow-tree
scenes. Native builds and headless regressions have not been run in
this tool session, so performance and runtime correctness are still
unverified on the target compiler/engine.
