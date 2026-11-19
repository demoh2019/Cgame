# Convex BVH child pruning

Cgame uses a shared dynamic BVH for physics and spatial queries. Inspired by
the child-bounds filtering used by Box2D's dynamic tree and Jolt's broadphase,
this patch changes the *buffered convex-volume traversal* in
`core/math/bvh_cull.inc`:

- Reject a disjoint root **before** creating the iterative traversal and
  convex cutting-plane stacks.
- Classify each child **before pushing it**, so disjoint children never
  occupy a stack slot or require a later pop.
- Propagate the `IR_FULL` classification to fully contained subtrees;
  those subtrees avoid additional convex-plane tests.
- Preserve child insertion order, per-tree masks, result capacity and exact
  leaf-level checks (including the existing optimized cutting-plane test).

The root and each partially intersecting child are classified once, not
once while pushing and again when popped. This doesn't change which proxies
the query returns. It trades more per-parent conditional branches for fewer
stack operations and useless subtree traversal. It may not improve every
scene; benchmark sparse frustum misses and dense fully-contained queries
separately.

## Verification

```bash
# Source-level contracts; these do not establish native correctness:
python3 -m unittest discover -s tests/stress -p test_bvh_convex_pruning.py -v

# Requires a Cgame native editor built with tests=yes:
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[BVH] 3D convex traversal prunes sparse subtrees without losing hits"

# Run the full BVH regression suite and compare with the develop baseline:
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test --test-case="[BVH]"
```

The new native C++ test creates 96 separated 3D bodies across two collision
trees and exercises miss, partial, fully contained, slanted cutting plane,
tree mask, result cap, move and deletion cases.

Before merging, run a native editor build with tests and compare query
latency/allocated stack overhead on the same hardware for representative
frustum scenes. No numeric speedup or reduction in RSS is assumed.

Upstream background:
- Box2D dynamic tree: https://box2d.org/documentation/group__tree.html
- Jolt broadphase architecture:
  https://github.com/jrouwe/JoltPhysics/blob/master/Docs/Architecture.md
