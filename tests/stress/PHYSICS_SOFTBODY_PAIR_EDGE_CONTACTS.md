# Godot Physics 3D — SoftBody pair edge/edge contacts

Experimental **discrete edge–edge contacts between different SoftBody3D
meshes** extend vertex/face, swept vertex/face CCD and dynamic pair friction.
The general approach is consistent with deformable surface-contact
capabilities in Bullet's cloth/soft-body pipeline and the more detailed
FEM surface contacts in PhysX. This is an independently implemented CPU
XPBD constraint; no Bullet or PhysX code is copied into Cgame.

## Enabling

Under `physics/3d/solver`:

- Set `soft_body_pair_collision_thickness > 0` to enable pair collisions.
- Set `soft_body_pair_collision_edge_edge = true` (default false).
- `soft_body_pair_collision_compliance` controls XPBD softness.
- `soft_body_pair_max_contacts` caps the combined vertex/face, CCD and
  edge/edge contact candidates per body pair (default 256).
- `soft_body_pair_max_pairs` and the existing global 16,384 pair AABB
  test budget remain in effect.

Inter-body edge contacts do **not** require enabling self-collision or
self-collision edge contacts.

## Algorithm

1. On first eligible pair, build a deduplicated structural edge list
   from each body's triangle mesh. A separate edge BVH holds pointers to
   the fully constructed array. Mesh changes clear it; disabled scenes
   allocate no tree nodes or edge lists.
2. Refit the edge BVHs at their current positions; query nearby edges
   using thickness-grown segment AABBs. Reject pinned-pinned and
   degenerate/parallel/outside-segment cases.
3. Record a bounded set of contacts (up to eight per edge and the
   remaining shared per-pair budget) **before** moving any nodes.
4. Iterate the existing unilateral XPBD edge/edge constraint up to four
   times. Signed contact normals remain fixed. Apply position deltas
   to velocities transactionally as `delta_x/delta_t` because the pair
   stage runs after local velocity reconstruction.
5. The pair stage refits spatial bounds, normals and face BVHs after
   any edge or vertex contact displacement.

If pair CCD history exists, it is used to retain the previous separation
side for a contact, but **the edge stage itself is discrete**. This does
not yet find swept edge/edge TOI or solve static/dynamic edge friction.

## Tests

- `tests/servers/test_physics_softbody_pair_edge_contact.cpp`: 6 native
  Doctest cases (crossing edges, masses, pins, invalid inputs).
- `tests/stress/test_physics_softbody_pair_edge_contact.py`: 4,000
  deterministic physical-reference samples and source wiring.
- `.github/workflows/physics-softbody-pair-edges.yml` runs the
  Python contracts on changed PRs and develop pushes.

### Remaining limitations

Edges must have interior nonparallel closest points in the current frame.
Fast-moving edges can tunnel; coplanar, parallel, endpoint or edge-edge
TOI contacts are not handled by this stage. The BVH is lazily built and
has additional RAM/CPU cost when enabled. Budgeted contacts may miss some
crowded mesh pairs. A full native engine build and representative
scene-level benchmarks remain necessary before production use.
