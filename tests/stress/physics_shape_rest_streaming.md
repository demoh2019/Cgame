# Streaming GodotPhysics shape and rest queries (2D / 3D)

## Issue

The built-in GodotPhysics 2D and 3D implementation previously collected up
to **2048 AABB candidates** for each direct-space query and only *afterwards*
ran collision-layer checks, RID exclusions, body/area filtering, and exact
narrowphase. A crowded, layered scene could fill this buffer with rejected
proxies, causing a **false negative** (or wrong best rest contact) even when
the correct shape was in the same world.

The affected APIs were:
- `PhysicsDirectSpaceState2D/3D.intersect_shape()`;
- `PhysicsDirectSpaceState2D/3D.collide_shape()`;
- `PhysicsDirectSpaceState2D/3D.get_rest_info()`.

## New traversal

These operations reuse `GodotBroadPhase2D/3D::visit_aabb()`, the streaming
BVH visitor introduced for `intersect_point()`. Rather than filling a
fixed-capacity scratch array, the visitor examines each AABB candidate and
runs filtering *before* narrowphase.

- `intersect_shape` stops as soon as the caller's **actual** results capacity
  is reached (and continues when a proxy is masked out, excluded, or misses
  the exact geometry test).
- `collide_shape` stops once the requested contact-position capacity is
  reached. Exact collision data is still collected by Godot's existing
  contact callback.
- `rest_info` visits **all** overlapping candidates because the deepest
  valid contact must win. The former 2048-proxy limit could hide this best
  contact even after a valid one was found.

The query maintains original 2D swept-AABB/margin handling and original 3D
intersection AABB semantics, collision masks, exclusions and body/area
filtering. It uses the BVH's existing iterative traversal stack and adds no
new allocation or state per body. The broadphase visitor is called under
the BVH's normal query lock: its narrowphase callbacks must not modify the
tree. Existing bounded internal `cull_aabb` users, including physics motion
casting, are not changed by this patch.

This follows the callback-based AABB queries in Box2D and the early filtering
principle described by Jolt Physics. No external source code is imported.

## Runtime regression

The companion GDScript script creates 4096 overlapping but wrong-layer
static colliders and one final matching collider in both 2D and 3D worlds.
It checks all three direct-space query APIs as well as wrong-layer,
body-disabled and explicit RID-exclusion results.

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path tests/stress \
  --script res://physics_shape_rest_overflow_regression.gd
```

Run with the project's **built-in GodotPhysics** backend selected. A successful
run verifies the regression; it does not imply an FPS or throughput gain.
The script reports the combined query latency (`query_us`) for A/B
comparisons. Prefer the same CPU, engine configuration, object count and
collider shapes when measuring.

C++ build/tests and this script must still be run on target platforms.
