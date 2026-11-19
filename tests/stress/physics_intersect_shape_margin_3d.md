# 3D intersect_shape: broadphase must account for query margin

`GodotPhysicsDirectSpaceState3D::intersect_shape()` already passed its
`p_parameters.margin` to `GodotCollisionSolver3D::solve_static()` (SAT
narrowphase), but its broadphase query searched only the original
unexpanded query shape AABB. The BVH could therefore cull a shape lying
within the **requested margin** before the exact collision solver ever
saw it.

The fix grows the query's world-space AABB by the **nonnegative** margin,
matching the behavior used by other 3D shape queries and ensuring
the candidate set is conservative with respect to narrowphase.

```cpp
const AABB aabb = p_parameters.transform.xform(shape->get_aabb()).grow(
        MAX(p_parameters.margin, real_t(0.0)));
```

The margin is applied to query candidates, not collider transforms.
Negative values do not shrink the broadphase query. This changes
only `intersect_shape()`, not collision filter behavior, the SAT
geometry, other queries or the public API.

## Regression

`physics_intersect_shape_margin_3d_regression.gd` places two radius-1
spheres 2.1 units apart (0.1 gap). The expected results are:

- margin 0.0: no intersection;
- margin 0.25: one intersection with the target collider;
- wrong collision layer or explicitly excluded RID: no intersection;
- target moved to x=2.5 (gap 0.5) with margin 0.25: no intersection.

The scenario is deterministic and reports one query latency sample
(`query_us`); one sample is **not a performance benchmark**.

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path tests/stress \
  --script res://physics_intersect_shape_margin_3d_regression.gd

python3 -m unittest discover -s tests/stress \
  -p 'test_physics_intersect_shape_margin_3d.py' -v
```

The Python checks validate the source/data-flow contract and 1D AABB
arithmetic, not the C++ narrowphase runtime. Full engine compilation and
headless execution remain necessary before production release.
