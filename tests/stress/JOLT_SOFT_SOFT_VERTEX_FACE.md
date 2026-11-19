# Cgame: vertex–triangle collisions between Jolt soft bodies

Jolt's native soft body pipeline handles soft–rigid contacts, not
soft–soft. Cgame's previous experimental CPU mode checked pairs of
surface vertices; when a vertex approaches the **interior of a large
triangle**, no vertex–vertex pair may be close enough to collide.

This iteration adds an **opt-in, discrete vertex–face mode**, using
ideas from Bullet's VF_SS approach. It computes the nearest point
on a deformable face (including edges and triangle corners), then
applies a two-way, barycentric mass-weighted normal impulse with
bounded velocity recovery and Coulomb-limited tangential friction.

This is *not* a port of Bullet, does not include Bullet code and
does not claim complete soft-body collision handling.

## Settings

Under `physics/jolt_physics_3d/simulation/`:

- `soft_body_soft_contacts = true`: master opt-in (default false)
- `soft_body_soft_vertex_face_contacts = true`: enable new mode
  (default false, preserving the existing particle-particle mode)
- `soft_body_soft_contact_radius = 0.1` (default, 0..1 m)
- `soft_body_soft_contact_recovery = 0.2` (0..1)
- `soft_body_soft_contact_friction = 0.2` (0..1)
- `soft_body_soft_contact_max_particle_pairs = 32768` (1024..65536)

The final setting bounds **point–triangle evaluations** when VF mode is
enabled; its name is retained for compatibility. Body pair checks remain
bounded to 2048 per physics step. At most one soft-soft contact solver
runs for each candidate body pair; the VV and VF modes are mutually exclusive.

## Method

For a soft body pair passing collision masks/exception filtering and
world-space AABB overlap:

1. Check surface particles of body A vs triangles of body B.
2. Repeat with surface particles of B vs triangles of A.
3. Find the closest point using the Ericson seven-region triangle
   projection and derive barycentric `u, v, w`.
4. Evaluate contact if the distance is below the configured radius.
5. For inverse masses `w_p, w_0, w_1, w_2`, the effective inverse mass
   is `w_p + u²w_0 + v²w_1 + w²w_2`.
6. Compute separating normal impulse and tangential Coulomb friction.
7. Apply impulse to the point and opposite weighted impulses to face
   particles using the current body rotations.
8. Reject degenerate geometry/nonfinite conditions and stop at the
   global work budget.

The solver runs pre-step and updates particle velocities; no massless
surface is assumed. Face vertices with zero inverse mass remain pinned.
Interior centroid particles from the earlier convex tetra fan are
excluded from the *point* side and do not appear in the surface faces.

No new heap allocations are required in the contact loop.

## Known limitations

- Still discrete; fast particles can tunnel through faces.
- No continuous collision detection, face–face or edge–edge contacts,
  self collision or persistent manifold cache.
- Surface-winding is ignored except for the exact-coincidence fallback
  normal (otherwise contacts are two-sided).
- This is **impulse-only**, not an XPBD positional projection; deep
  overlap can need multiple steps for separation.
- Global work limit makes the result order-dependent in crowded scenes.
- Current broadphase is per-body AABB; large overlapping meshes can
  saturate the budget on distant point/face combinations. A triangle
  BVH or spatial grid is a worthwhile next optimization.
- The underlying native build has not yet been verified in this
  environment; treat this as experimental until CI passes.

## Verification

Reference math and source contracts:

    python3 -m unittest tests/stress/test_jolt_soft_soft_vertex_face.py -v

Native Godot regression (requires compiled Cgame editor):

    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
        --path tests/stress/jolt_soft_soft_vertex_face \
        --script res://vertex_face_regression.gd

The native scene uses a sparse anchored triangle and tetrahedron, plus
a second masked control pair. Check displacement, finite vertices, pinned
anchors and frame timings. Benchmark with the feature off, VV only,
and VF enabled using identical scene geometry. Native runtime and
performance tests are required before shipping this mode by default.
