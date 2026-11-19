# Cgame/Jolt: persistent and refittable self vertex–face BVH

## Comparison and motivation

Jolt's soft bodies use XPBD for internal constraints, but its published
architecture still limits built-in soft-body collision to rigid bodies.
Bullet, in contrast, maintains separate dynamic bounding-volume trees
for soft-body faces and nodes. Its deformable CCD path calls
`updateFaceTree` and `updateNodeTree` instead of sorting an entirely
new tree for every contact query.

Cgame's experimental single-body self **vertex–triangle** contact solver
already supports discrete contacts, a Jacobi position correction, and
linearized conservative-advancement CCD. Its self-face BVH was previously
rebuilt from scratch every physics frame, even though the mesh topology
and identity of each face are unchanged.

This patch implements a **per-body persistent self-face BVH with
bottom-up refitting**. It borrows the broadphase idea only; no Bullet
or other engine source code is copied.

## Enable

Under `physics/jolt_physics_3d/simulation/`:

- `soft_body_self_contacts=true`
- `soft_body_self_face_bvh_refit=true` (**new, default false**)
- `soft_body_self_contact_max_checks=32768` or higher for dense cloth

This mode **does not require self edge-edge collision**,
`soft_body_self_edge_bvh`, or
`soft_body_self_persistent_bvh`. It works with existing self
vertex–face speculative CCD and positional contact projection.

The old default rebuild path remains unchanged when the new option is
disabled. Even when enabled, small meshes with fewer than 32 faces
continue to use the original direct scan.

## Internal representation

Reuses `SoftFaceBVHEntry` and `SoftFaceBVHNode`, where every entry
stores its **original triangle index**, even after median splitting.
Leaves have at most four faces. The scratch BVH and immutable one-ring
topology are stored in the existing **64-body-per-space,
generation-aware cache**, evicted by `remove_object`.

Initial construction builds the ordinary bounded face BVH with
`prepare_soft_face_bvh`. On subsequent steps:

1. Verify face-array identity, face count and vertex count through
   `ensure_soft_self_topology`. A topology mismatch invalidates both
   the face BVH and edge BVH before any query.
2. Refresh each entry's AABB from the **current positions of all
   three face vertices**, checking indices, degeneracy and finiteness.
   Face order is not changed.
3. Walk nodes in **reverse pre-order construction order**: first union
   the entries in each leaf, then combine each internal node's two
   already-updated children. No median sort is needed.
4. Query the existing self VF narrowphase using the refitted tree.
   Contact normals, barycentrics, topology exclusions, friction,
   pinned particles, speculative CCD radius and XPBD-style projection
   are preserved.
5. After **120 successful refits**, rebuild the median hierarchy to
   restore culling quality after strong folding or stretching.
6. If any source face becomes invalid, or the refit fails its work
   quota or validation, discard the partial tree and try the existing
   **budgeted full rebuild**. If that also fails, skip this VF pass
   exactly as before; never query partially refitted bounds.

### Budget and safety

All refits debit `4 * valid_face_entry_count + bvh_node_count`
units **before** the work begins. Full rebuild still charges the old
conservative `F * (ceil(log2(F)) + 1)` units. Traversed nodes and exact
candidate checks continue to debit the global self VF budget.

The existing self-VF cap of **1024 faces per body** remains. The space
retains at most **64 bodies' caches**; excess bodies use uncached
scratch. The cache is freed on body destruction, space destruction or
when every persistent collision mode is disabled. There are no
per-contact heap allocations in this change.

## Tests

Mathematical and source contracts:

    python3 -m unittest tests/stress/test_jolt_soft_self_face_bvh_refit.py -v

Native regression (requires a compiled Cgame editor with Jolt enabled):

    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
      --path tests/stress/jolt_soft_self_face_bvh \
      --script res://persistent_face_bvh_regression.gd

The native fixture runs 152 frames on a self-intersecting 8×8 cloth
pair (196 triangle faces) plus a connected flat control, keeps self
edge collision disabled, checks finite particle positions and pinned
corners, crosses the 120-refit threshold, and removes/recreates the
primary soft body at frame 128 to check cache invalidation.

A passing scene demonstrates stability for this configuration, not a
speed improvement. To establish acceleration, profile identical cloth
and topology with `soft_body_self_face_bvh_refit` on/off, recording
physics-step latency, allocations, peak RSS and collision misses.

## Limitations / next features

- BVH median partitions remain fixed between rebuilds. A cloth that
  folds severely may traverse more nodes until the 120-refit reset.
- No persistent contact manifolds or warm-started Lagrange multipliers.
- This patch does **not** introduce FEM elasticity, tearing, plasticity,
  or exact CCD for accelerating soft particles.
- Native C++ compilation and physical stress pass are required before
  production use. Reference-model tests do not establish native
  correctness or measured FPS gains.
