# Streaming AABB BVH: fully covered subtree fast path

## Problem

Cgame's callback-based `BVH_Tree::visit_aabb()` is used by GodotPhysics
2D/3D point/shape queries, motion casts and body-motion queries. It avoids
the historical 2048-proxy output cap, but formerly tested the AABB of
**every** child and leaf proxy even when the requested AABB completely
enclosed an entire subtree.

The existing *bounded* `cull_aabb()` already used a `fully_within` flag.
This change applies the same traversal invariant to **streaming visitors**.

## Implementation

- At the root, test intersection once and determine whether the query
  completely contains the root bounds.
- Carry `fully_within` through the iterative BVH stack. When true, visit
  descendants without redundant AABB intersection or containment tests.
- When a child only partially overlaps, check its AABB once before pushing
  it (rather than testing at both push and pop).
- Pre-swizzle the query once for dense leaves when partial-overlap testing
  is required, following the existing bounded `cull_aabb` hot path.
- Preserve collision tree masks, optional user cull checks, leaf item
  order, callback early termination, and all narrowphase filtering.
- Add only a boolean to each *transient* traversal stack entry; there is
  **no per-collider or per-query heap buffer**.

This is similar to the subtree rejection/collector principles used by
Box2D's dynamic tree and Jolt's broadphase queries, and builds on the
algorithm already present in Cgame's bounded AABB traversal. No external
physics engine source was copied.

## Regression tests

New native C++ test `tests/core/math/test_bvh_aabb_visitor_containment.cpp`
constructs 256 proxies in both 2D and 3D trees and verifies a full-cover,
no-cover, and 98 mixed queries in each dimension. It checks every returned
proxy against a brute-force packed-AABB reference, collision tree masks,
no duplicates, and callback early termination.

The runtime regression exercises 4,096 static bodies per dimension, using
full-cover and partial-cover `intersect_shape` queries, early result caps
and collision masks. It reports `full_query_us` and `partial_query_us`
for baseline comparison:

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path tests/stress \
  --script res://physics_bvh_full_cover_regression.gd
```

For native tests, build with `tests=yes` and run the `[BVH]` cases.
Python reference cross-check (not the C++ engine) confirmed equal hit sets
for **5,000** synthetic random queries across 2D/3D trees. On full-cover
queries, the simulated tree did only one root bounds test instead of one
per node; this is an operation count, **not** a measured FPS speedup.

## Caveats

The extra containment check can cost some instructions for queries that
intersect many nodes without fully covering any subtree, and dense
near-identical proxies may still spend most time in narrowphase. Measure
CPU, allocations and peak RSS against the same scene on the same hardware.
No C++ build, native tests, GDScript tests or A/B performance benchmarks
have been run in this session because the connected build host is offline.
