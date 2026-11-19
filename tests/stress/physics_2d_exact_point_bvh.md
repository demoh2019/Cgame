# Exact BVH point traversal for GodotPhysics 2D

## Gap addressed

GodotPhysics 3D already forwards point queries directly to
`BVH_Manager::visit_point()`. GodotPhysics 2D instead built an artificial
`Rect2(position - Vector2(0.00001, 0.00001), Vector2(0.00002, 0.00002))`
and called `visit_aabb()`. This increases the candidate set by accepting
collider AABBs that are merely *near* the point. In crowded scenes that
can trigger thousands of unnecessary transforms and `contains_point()`
narrowphase tests.

Dynamic BVHs in Box2D and Jolt use hierarchical rejection of candidates,
followed by exact per-shape checks. Cgame's own BVH already supported
native 2D point traversal, but the 2D broadphase interface did not
expose it. No third-party source is imported.

## Implementation

- Added `visit_point(Vector2, QueryVisitor, void *)` to the internal
  `GodotBroadPhase2D` abstraction and `GodotBroadPhase2DBVH`.
- Forwarded this call to the existing `BVH_Manager::visit_point()`.
- Updated `GodotPhysicsDirectSpaceState2D::intersect_point()` to call
  the exact traversal directly, instead of constructing a tiny AABB.
- Preserved `collision_mask`, body/area flags, excluded RIDs,
  `pick_point`, canvas ID filtering, exact `contains_point()` and
  early termination after `max_results` real hits.

No per-body memory, allocation, persistent cache or public Godot
scripting API is added. The code uses an existing BVH query algorithm;
its exact containment differs from the historical epsilon-broadened
candidate set, but exact narrowphase still decides actual hits.
In unusual affine transforms or boundary rounding cases, verify
regressions on the actual engine rather than assuming bitwise identity.

## Tests

The native `tests/core/math/test_bvh_2d_exact_point.cpp` creates
**4096 AABBs** at x=0.000005 that overlap the historical epsilon query
but do not contain the origin, plus one real target AABB inserted last.
It contrasts the two visitors and tests tree masks and early termination.

The headless script
`tests/stress/physics_2d_exact_point_bvh_regression.gd` creates
**4096 near-but-outside static circles** and a single exact target;
repeats 64 origin queries, verifies the target and a point actually
inside the decoys, exclusion and mask filtering, and the result after
the target shape and parent transforms change.

```bash
python3 -m unittest discover -s tests/stress \
  -p 'test_physics_2d_exact_point_bvh.py' -v

./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path tests/stress \
  --script res://physics_2d_exact_point_bvh_regression.gd
```

Build Cgame with `tests=yes` and run the `[BVH]` native suite.
Compare query latency (including a high-density epsilon-close scene)
on identical builds and hardware. No measured FPS/RAM benefit,
successful native compilation or completed CI is asserted here.
