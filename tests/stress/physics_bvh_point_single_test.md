# BVH point query: single AABB test per visited node

## Inspiration

Box2D dynamic-tree queries invoke callbacks for broadphase candidates and
filter by category bits before invoking the exact shape cast; Rapier's scene
queries reuse its BVH broadphase and filter candidates through a query
pipeline. Following the same traversal design, this change removes duplicate
node-bound checks in Cgame's streaming BVH point visitor.

## Change

Before: `_visit_point_iterative()` tested every child AABB when adding that
child to its iterative traversal stack **and tested the same AABB again**
immediately after popping it. This caused redundant AABB operations for
successful child nodes.

After: test the selected root AABB once. Every child pushed onto the stack
has already passed `intersects_point()`, so the pop loop can proceed directly
to the node's leaf or children. The leaf-proxy checks remain unchanged.

All callback behavior, tree collision masks, tester filters, child visitation
order and early termination remain exactly the same. No extra per-body state,
persistent cache or heap allocation is introduced. The unchanged iterative
stack still handles very deep BVHs via its existing overflow path.

## Tests

`tests/core/math/test_bvh_point_visitor.cpp` includes two native test cases
(2D and 3D), each using 512 spatial proxies and 240 deterministic test
points. It validates every candidate against packed-AABB brute force,
including empty queries, tree masks, all bounding-box boundaries,
duplicate avoidance, and early termination. Build Cgame with `tests=yes`
and run the `[BVH]` test cases.

Existing end-to-end point regression can also be run:

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path tests/stress \
  --script res://physics_point_query_overflow_regression.gd
```

Independent synthetic Python traversal comparison: 10,000 queries on
512-proxy trees in 2D/3D (10,000 combined), **zero hit-set mismatches**;
bounds checks fell from 2,673,740 to 1,552,388 in that *synthetic tree*,
a 41.9% reduction in node-bound checks. This is not a real Cgame benchmark
or an FPS/RSS claim. In real scenes, the performance gain will depend on
tree depth, hit rate, filtering and the cost of the narrowphase callback.

C++ compilation and native Godot tests are not yet verified: the connected
Mac build host is offline. Measure physical query throughput and memory
on target hardware before claiming a production speedup.
