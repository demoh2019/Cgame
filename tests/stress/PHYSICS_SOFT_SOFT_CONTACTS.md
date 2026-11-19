# Godot Physics 3D: experimental soft body vs soft body contacts

A discrete, opt-in, **two-way** SoftBody3D–SoftBody3D vertex/triangle
contact stage. Bullet's vertex-vs-face soft-body collision mode is the
conceptual reference. It does not modify the Jolt Physics backend, and
it is NOT a complete tetrahedral FEM, CCD, or cluster-cluster solver.

## Project settings

- `physics/3d/solver/soft_body_pair_collision_thickness` — surface
  separation thickness, metres (default **0**, disabled).
- `physics/3d/solver/soft_body_pair_collision_compliance` — XPBD compliance
  (default 0.000001; **0** is an incompressible contact constraint).
- `physics/3d/solver/soft_body_pair_max_contacts` — maximum temporary
  candidate contacts per body pair (default 256, hard cap 2048).
- `physics/3d/solver/soft_body_pair_max_pairs` — maximum overlapping
  body pairs inspected per physics tick (default 128, hard cap 512).

An independent **16,384 pair-AABB-check budget** prevents pathological
O(number_of_soft_bodies²) frame spikes. Excess contacts/pairs are deferred
to future physics ticks; this first implementation does not guarantee
fairness among those deferred candidates. Each node contributes at most
8 contacts for each direction of a body pair.

## Collision stage

1. Finish each soft body's own stretch, bend, volume, self-contact and
   rigid-body interactions.
2. Compare soft-body world AABBs, collision layers/masks and exceptions.
3. Query each mesh's triangle BVH for the OTHER body's nearby vertices.
   Collect candidate contacts before moving any nodes.
4. Solve 1–4 local XPBD iterations. Inverse-mass-weighted corrections
   move the vertex and the contacted face in opposite directions. Zero
   inverse mass preserves pins exactly. A unilateral multiplier cannot
   artificially pull separated bodies together.
5. Reconstruct the position-correction contribution to velocities and
   refit node/face BVHs, normals and world bounds for later pairs/queries.

The velocity and position updates are transactional: any invalid or
unrepresentable correction leaves all four particles unchanged.

## Validation

- `tests/servers/test_physics_softbody_pair_contact.cpp` covers
  two-way impulse, pinned vertices/faces, separation and failure paths.
- `tests/stress/test_physics_softbody_pair_contact.py` compares a
  mass-weighted numerical reference over 2,000 random contacts and
  checks configuration/source integration.
- `.github/workflows/physics-softbody-pair-contact.yml` runs the Python
  numerical contracts on PR and develop changes.

**Important limitations:** This is discrete point-face proximity,
not swept TOI/CCD. Very fast or grazing interactions may tunnel. It
does not yet handle edge-edge collisions between separate soft bodies,
soft-soft friction, clusters, or self-consistent substepping. The AABB
pair-selection stage has fixed work budgets and can miss pairs when
there are many active soft bodies. Benchmark and verify the integration
in a compiled engine before shipping a gameplay project.

Manual integration tests: two overlapping soft balls, two crossing cloth
patches, pinned cloth against movable cloth, all-static pairs, masks
and exceptions, large crowds of separated soft bodies, teleportation
and high-speed motion, 30/60/120 physics ticks, stress scenes with
thousands of vertices, and 32-bit/64-bit real_t builds.
