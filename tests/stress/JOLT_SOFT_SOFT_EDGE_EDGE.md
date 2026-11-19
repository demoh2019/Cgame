# Cgame: experimental deformable edge-to-edge soft-body contacts

## Background

Jolt Physics currently has only soft-body versus rigid-body native contacts;
Bullet supports soft-body vertex/face and clustered interactions. Existing
Cgame modules add vertex–vertex (PR #607), vertex–face (PR #610), and
per-pair face BVH acceleration (PR #615). A missing collision case is two
triangle *edges crossing near their interiors*, where no endpoint is close
enough to any opposing triangle to create a vertex–face contact.

This adds an experimental **edge–edge** contact pass alongside the VF pass.
No Bullet code is copied. The approach follows closest-segment geometry and
effective inverse-mass impulse distribution used by particle systems.

## How to enable

Project Settings > Physics > Jolt Physics 3D > Simulation:

- `soft_body_soft_contacts = true` (master, otherwise no work)
- `soft_body_soft_vertex_face_contacts = true` (keeps the VF pass)
- `soft_body_soft_edge_edge_contacts = true` (new, default **false**)
- `soft_body_soft_contact_radius = 0.1` (proximity envelope)
- `soft_body_soft_contact_recovery = 0.2` (velocity bias)
- `soft_body_soft_contact_friction = 0.2` (Coulomb limit)
- `soft_body_soft_contact_max_particle_pairs = 32768` (work units)

When edge contacts are enabled, the solver reserves half the work budget for
edge contacts and half for existing VF contacts; it does **not double** the
configured total work. This quota is per world/space physics step, not per
body. Mask/exceptions and expanded AABB filtering still apply.

## Algorithm and performance

1. Enumerate the current soft-body *surface faces* (max 512 per body).
2. Collect the three edges of each face, encode sorted vertex indices and
   sort/unique them. Shared edges are processed exactly once.
3. Charge the O(F log F) edge extraction/sorting cost against the dedicated
   budget. A body beyond size limits or an exhausted budget is skipped.
4. Per candidate edge pair, use conservative expanded AABB rejection.
5. Solve the closest parameters on two finite segments (including parallel
   and endpoint configurations), and reject pairs beyond contact radius.
6. For weights `(1-s,s)` and `(1-t,t)`, compute effective inverse mass
   `(1-s)²m0^-1+s²m1^-1+(1-t)²m2^-1+t²m3^-1`.
7. Apply a bounded normal velocity correction and Coulomb-limited friction,
   distributing opposite impulses to all four endpoints.
8. Pinned vertices have inverse mass zero; their velocities are untouched.
   Exact crossings fall back to cross-product normal oriented using center
   difference to choose a separating direction.

Edge lists are backed by two Jolt arrays reused across all soft-body pairs
within the step. The pair loop runs only if masks/exceptions and world-space
AABB overlap allow it. The common default-off path allocates no edge arrays.

**Limitations:** discrete proximity (not CCD); no full triangle/triangle
intersection, no soft self-collision, no persistent manifold, no edge BVH.
The O(E_A×E_B) inner loop is limited by global work budget; dense surfaces
may exhaust the quota and skip further soft-body pairs. Degenerate edges
are rejected. This is *not* FEM nor cloth tearing, and does not make all
possible soft-soft configurations collision-safe.

## Verification

Python source and independent segment math:

    python3 -m unittest tests/stress/test_jolt_soft_soft_edge_edge.py -v

Native Cgame Jolt scene:

    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
        --path tests/stress/jolt_soft_soft_edges \
        --script res://edge_edge_regression.gd

The scene uses two crossing, single-face soft triangles with their third
tips pinned, plus a collision-masked duplicate pair. The two crossing
edges should separate along the Z axis without moving the masked control.

Before promoting this feature to a default, validate actual native C++
compilation, stability for pathological parallel/coplanar segments, and
FPS/RAM at 2, 16, 64 and 256 interacting bodies.
