# Cached BVH ray entries: fewer redundant slab tests

## Design comparison

Box2D's dynamic tree casts rays through a callback that can clip the maximum
ray fraction after each exact hit, and Jolt Physics uses a similar early-out
fraction in its broadphase collision collectors. Cgame already adopted this
pattern with near-first BVH traversal, but its ray walker still repeated an
expensive ray/AABB *slab intersection* for nodes that had passed the same
test just before being pushed onto its iterative stack.

The fix keeps the entry fraction from the first slab test in each stack item,
and tests `entry_fraction > current_max_fraction + CMP_EPSILON` on pop.
This avoids recalculating slab intersections for already-qualified nodes.

**The critical invariant is that all cached entries must be fractions of
the same original ray**. Shortening the stored segment endpoints mid-traversal
would make fractions in old stack items incomparable. The traversal now
keeps the original segment intact and uses `r_max_fraction` for clipping.
It also skips later root trees when their already sorted entry fractions
cannot improve the closest hit.

For dense leaves, the nearest-proxy-first hint and narrowphase callbacks
remain intact. Each leaf proxy is checked against the original segment,
then rejected when its entry is beyond the current maximum fraction.
The small tolerance preserves boundary/grazing results despite
floating-point roundoff. No public API changes or source copying.

The runtime BVH nodes and collider memory layout are **unchanged**.
A transient stack entry stores an additional `real_t` alongside its node ID.
This may moderately increase temporary stack use; it does not allocate a
candidate vector or retain per-collider metadata.

## Correctness and stress tests

- `tests/core/math/test_bvh_ray_entry_cache.cpp`: 512 box proxies per
  dimension and 360 deterministic rays in 2D and 3D. Each ray is exercised
  with both unfiltered and simulated narrowphase-rejected proxies,
  masks 0/1/2/3, reversed and degenerate rays, and a **brute-force
  original-ray AABB reference** for the nearest hit.
- Existing native `test_bvh_dense_leaf.cpp` covers nearest-first
  scheduling of 64 proxies in a single leaf, the initially ignored
  closest proxy, and reversed casts.
- `tests/stress/physics_bvh_ray_entry_cache_regression.gd`: 4,096 static
  colliders per dimension, repeated nearest-ray queries, explicit RID
  exclusion (next object must win), reverse casting (last object must win),
  and nonmatching collision masks.

Run native tests after compiling Cgame with `tests=yes`; run the
physics stress script with the built-in GodotPhysics backend:

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path tests/stress \
  --script res://physics_bvh_ray_entry_cache_regression.gd
```

## Synthetic traversal reference and caveats

An independent Python model with 512 AABBs in two binary trees exercised
**5,000 random rays** with optional filtering and collision masks.
The old clipped-segment walker and the new original-entry walker agreed
on the nearest hit on every case (zero mismatches). The model counted
244,968 old versus 153,910 new AABB slab tests (~37.2% fewer in the
synthetic model). This is not an engine FPS/RSS benchmark or a run of
the added C++ and GDScript tests.

The performance benefit depends on tree depth, scene density, clipped
fraction and early-out success. Full-ray testing may do more work in
some distributions than old clipped segment queries. Benchmark both
near-hit and miss-heavy scenes against the same Cgame build configuration.

C++ compilation, actual Godot tests and runtime CPU/memory metrics still
need confirmation on the build host.
