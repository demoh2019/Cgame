# Unbounded, early-filtered point queries (GodotPhysics 2D / 3D)

GodotPhysics previously collected **at most 2048 broadphase candidates**
before running the requested collision-mask, exclusion and narrowphase tests
in `PhysicsDirectSpaceState2D::intersect_point` and
`PhysicsDirectSpaceState3D::intersect_point`. In dense or layered scenes, all
2048 slots could be consumed by filtered-out bodies, returning zero valid hits
even if a matching collider existed elsewhere in the BVH.

Point queries now traverse the BVH using an **allocation-free callback**.
Every overlapping proxy is tested against the actual query filters before it
occupies one of the caller's `max_results` slots. Traversal stops once the
requested number of **accepted** hits is reached, rather than stopping after
a fixed number of intermediate candidates.

The existing array-based BVH `cull_aabb`, `cull_point`, and other shape
queries retain their original behavior. Raycasts already use a separate
streaming visitor. This change does not promise a throughput improvement
for all workloads; callback overhead can offset avoided candidate buffering.

## Native C++ tests

Build the engine with `tests=yes` and run the `[BVH]` cases. The new file
`tests/core/math/test_bvh_stream_query.cpp` tests 4096 overlapping proxies
in both dimensions, correct filtered results beyond the original 2048
candidate cap, tree masks, early termination, and zero-mask short-circuiting.

## Direct-space runtime regression

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path tests/stress \
  --script res://physics_point_query_overflow_regression.gd
```

The script creates **4097 static colliders in each dimension** at the same
point. Only the final one is on collision layer 2. It checks that an
`intersect_point` query with mask 2 and `max_results = 1` finds that body,
and verifies negative layer, type, and RID-exclusion filters. It also reports
query latency in microseconds (`query_us`).

Run on a Cgame build with the built-in GodotPhysics backend selected.
Compare identical builds/scenes on the same machine, including query wall
time and peak RSS. The script is a correctness regression, not a million-
dynamic-body benchmark.
