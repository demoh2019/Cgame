# Cgame: persistent self-collision topology and refittable edge BVH

## Motivation / engine comparison

Bullet Physics keeps dynamic face/node/cluster AABB trees, and its
deformable collision code **updates/refits** those trees between collision
iterations. Cgame previously rebuilt the self-contact adjacency graph and
self edge BVH from scratch for each soft body **every physics frame**,
even though Jolt's `SoftBodySharedSettings` mesh topology is immutable.

This experimental mode caches the *connectivity* and the BVH *partition*
across physics frames, updating only the AABB bounds as the vertices deform.
It follows the broadphase principle, not code from Bullet or PhysX.

## Opt-in settings

Under `physics/jolt_physics_3d/simulation/`:

- `soft_body_self_contacts=true`
- `soft_body_self_edge_contacts=true`
- `soft_body_self_edge_bvh=true`
- `soft_body_self_persistent_bvh=true` (**new**, default false)
- `soft_body_self_contact_max_checks=32768` (sample; existing 1024..65536)

All four toggles must be true to retain topology and BVH between steps.
When off, the original scratch-only BVH rebuild and self VF/EE solvers are
unchanged. This is CPU self collision; inter-body soft-soft collision flags
are independent.

## How it works

A lazy, space-owned `JoltSelfCollisionCache` retains at most **64**
soft bodies, indexed by Jolt's full generation-aware `BodyID`.

### Topology

The edge list is made from sorted, deduplicated undirected triangle edges.
Its identity is the immutable Jolt face-array address and face/vertex
counts within a single BodyID. If this identity changes, the edge BVH
is invalidated and the topology is rebuilt before queries.

- Initial adjacency preparation still charges the conservative
  O(F log F) work budget.
- Reusing the existing sorted topology charges one budget unit instead
  of rebuilding it every frame.
- The self vertex-face and edge-edge passes share the same validated
  adjacency. Immediate one-ring spring neighbors remain excluded.

### BVH refitting

Initial BVH construction retains original edge indices in leaves,
while a median-split tree partitions AABBs into 4-edge leaves.

Each subsequent physics step:

1. Recalculate each segment AABB from its **current soft particle
   positions** and validate finite coordinates.
2. Walk BVH nodes in **reverse construction order**. Refit leaf bounds
   from edge entries; refit each parent from its two children. No
   repartitioning or sorting is needed.
3. Use the existing conservative AABB query, followed by the unchanged
   one-ring filter and exact segment–segment contact/impulse solver.
4. **After 120 successful refits**, rebuild the median tree to improve
   spatial quality following extensive folding and reconfiguration.
5. If a refit/rebuild is impossible under the remaining CPU budget, use
   the original linear fallback instead of leaving a stale BVH active.

The refit cost debited to the existing EE work budget is
`2 * valid_edge_count + bvh_node_count`, compared to an estimated
`E * (ceil(log2(E)) + 2)` budget for rebuilding. Node visits and exact
candidates still debit the global quota. No new per-contact allocation.

### Lifetime / memory safety

- **Body removed or mesh rebuilt:** `JoltSpace3D::remove_object`
  evicts the full BodyID's topology and BVH before destroying it.
- **Space destroyed:** the owned cache is deleted.
- **Feature disabled:** all persistent buffers are deleted at the next
  pre-step, restoring the old allocation behavior.
- **More than 64 bodies:** additional bodies temporarily use the old
  per-step scratch; the persistent cache never grows without bound.
- **Multiple spaces:** caches are isolated, never globally shared.

This does not retain Jolt `SoftBodyVertex*` pointers: only stable edge
indices, AABBs, node partitions, and a topology identity are cached.

## Validation

Python geometry and source contracts:

    python3 -m unittest tests/stress/test_jolt_soft_self_persistent_bvh.py \
      tests/stress/test_jolt_soft_self_edge_bvh.py \
      tests/stress/test_jolt_soft_self_edge_contacts.py \
      tests/stress/test_jolt_soft_self_contacts.py -v

Headless Cgame editor scene:

    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
      --path tests/stress/jolt_soft_self_persistent_bvh \
      --script res://persistent_refit_regression.gd

The scene runs for **152 frames** on two crossing 8x8 panels, triggers
the 120-refit periodic rebuilding threshold, destroys and recreates
the primary soft body at frame 128, and checks pinning, finite bounds,
finite particle coordinates and stability against a single flat grid.

A passing test proves functional sanity, **not an FPS speedup**. For
performance evidence, compare identical cloth workloads with persistent
BVH on/off and record physics-step latency, allocations and peak memory.

## Limitations and future work

- Node partitions are not incrementally *rotated*: a highly deformed
  mesh can have poor BVH culling until the 120-refit rebuild.
- Only edge BVH and shared adjacency persist; the existing self
  vertex-face BVH still rebuilds every step.
- Topology is assumed immutable during one Jolt BodyID. Dynamic mesh
  changes must reconstruct/remove the body (Godot/Cgame does this).
- Cached bodies consume additional persistent RAM, capped at 64 bodies
  per physics space.
- No full deformable CCD, self-edge manifold/warm-starting, XPBD
  positional projection, tearing, damage propagation, or volume FEM.
- Native compilation/runtime correctness and FPS/RAM have not been
  confirmed by this document or the reference Python tests.
