# Cgame: bounded BVH-accelerated self edge-edge collision (Jolt)

## Background

Bullet Physics uses dynamic bounding volume trees (DBVT) for soft-body
contact queries, while upstream Jolt documents no native soft versus soft
collision (including self-collision). Earlier Cgame PR #654 adds an opt-in
discrete soft-body self edge–edge impulse pass, but its O(E²) candidate
enumeration spends the entire budget on remote edge pairs in dense meshes.

This revision introduces an **optional deformed-edge BVH**. It does NOT
copy Bullet code or introduce a full persistent DBVT. The geometric
candidate filter is conservative, and the original closest-segment
narrowphase, topology exclusions, pinned points, mass-weighted impulses,
friction and inter-body collision options remain unchanged.

## Enable

Under `physics/jolt_physics_3d/simulation/`:

- `soft_body_self_contacts=true` (existing master, default false)
- `soft_body_self_edge_contacts=true` (existing edge mode, default false)
- `soft_body_self_edge_bvh=true` (**new**, default false)
- `soft_body_self_contact_max_checks=16384` (existing, 1024..65536 per
  space and step; the fixture uses 32768 to exercise the dense test)
- `soft_body_soft_contact_radius=0.1` metres (existing)

Enabling the edge BVH **does not increase the per-space budget**. When
edge contacts are on, the self-contact quota is split between vertex-face
and edge-edge contacts, as before. It does not require inter-body contacts
to be enabled.

## Implementation

1. Reuse the sorted unique triangle-surface edge list from the existing
   self VF/EE passes, and compute an AABB from each pair of **current**
   local soft-vertex positions. This reflects deformation each frame.
2. For meshes with **32–3072 unique edges**, and enough work budget,
   build a balanced median-split BVH using Cgame's existing BVH nodes.
   Each leaf contains up to four edge AABBs. The entry retains its
   **original edge key index**, even when the median splitter reorders
   the entry array.
3. For each edge, query overlapping AABBs of other edges with contact
   radius expansion. Charge **every visited node** from the self edge
   work budget and consider only conservative AABB candidates.
4. Keep the original unordered-pair condition `j > i` so no self pair
   receives an impulse twice. Apply the existing one-ring adjacency
   exclusion before segment narrowphase.
5. Run exact closest-segment and 4-particle impulse/friction as before,
   charging each candidate against the global work quota.
6. Skip building BVH when the mesh size is outside its supported range
   or the estimated O(E log E) build work cannot be afforded. Then use
   the **unchanged linear broadphase** as a fallback (also budgeted).

The tree is rebuilt for each active soft body per physics step, not
incrementally refitted. BVH entries, nodes, candidates and traversal stack
live in reusable Jolt scratch arrays allocated only when enabled and
reused across bodies within the step. Query time on spatially sparse
meshes is usually much lower than O(E²), but worst case remains bounded
by the configured work budget. A packed mesh whose edges all overlap
may receive little or no benefit and pay extra BVH construction cost.

### Counting and safety

The BVH builder charges `edge_count * (ceil(log2(edge_count))+2)`
conservative work units, traversal charges each visited node, and
narrowphase charges each candidate edge pair. Face adjacency construction
and VF contacts are already accounted for by their own share. When the
budget runs out, the solver skips remaining contacts instead of doing
unbounded work. This can produce order-dependent physical results.

Mesh surface topology is unaffected. Degenerate indices and nonfinite
bounds are rejected during BVH construction; old narrowphase finite/
degeneracy guards continue to apply. No additional allocations occur
in the inner contact loop.

## Tests

Independent reference geometry, randomized candidate equality,
corner/boundary queries, original-edge index preservation, structure,
work bounds, and source/config contracts:

    python3 -m unittest tests/stress/test_jolt_soft_self_edge_bvh.py \
        tests/stress/test_jolt_soft_self_edge_contacts.py -v

Native dense folded-cloth stability test, requiring compiled Cgame Jolt:

    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
      --path tests/stress/jolt_soft_self_edge_bvh \
      --script res://bvh_self_edges_regression.gd

The native fixture puts two perpendicularly crossing 8×8 panels
(196 faces total) into the same soft body. An independent adjacent 8×8
panel is the control. It verifies finite particle positions, bounded
displacements, pinned corners and reports elapsed test time.
A passing scene proves basic stability **not a performance speedup**.
Compare identical workloads with `soft_body_self_edge_bvh` toggled
and record step time and peak RSS before declaring a speed advantage.

## Remaining work

- Persistent/refittable per-object BVH to avoid rebuilding every frame.
- Caching immutable mesh adjacency with safe mesh invalidation.
- Deformable self CCD, contact manifolds and positional XPBD projection.
- Real stress profiling of large cloth, many bodies, GPU or FEM approaches.
- Native C++ compilation and runtime checks must pass before production use.
