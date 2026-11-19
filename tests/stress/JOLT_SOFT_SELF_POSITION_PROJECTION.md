# Cgame: compliance-weighted self-contact position projection (Jolt)

## Why this complements the current solver

Jolt soft bodies already use the **Extended Position Based Dynamics** (XPBD)
formulation for their internal stretch/bend/volume constraints. Upstream Jolt
documents no native soft-versus-soft or self collision, so Cgame has added
experimental CPU vertex-face and edge-edge self-contact *velocity impulses*.
Under deep overlap or near-zero relative velocity, a velocity-only contact
pass may reduce penetration slowly or require high artificial velocity bias.

This feature adds a **single, compliance-weighted Jacobi positional
correction** for self VF and self EE contacts. It follows the XPBD scalar
constraint formula but is **not** a complete multi-iteration, warm-started
XPBD contact solver: there is no persistent Lagrange multiplier, full
substep solve, or exact continuous self collision. PhysX uses FEM for its
GPU deformables; this code neither replaces FEM nor copies upstream code.

## Project settings (opt-in)

In `physics/jolt_physics_3d/simulation/`:

- `soft_body_self_contacts = true` (existing self-contact master)
- `soft_body_self_edge_contacts = true` (optional; enables self EE)
- `soft_body_self_position_projection = true` (**new**, default false)
- `soft_body_self_position_compliance = 0.000001` (new, 0..0.001)
- `soft_body_self_position_max_correction = 0.02` m (new, 0..0.1)
- `soft_body_self_contact_max_checks = 16384` (existing global work quota)
- `soft_body_soft_contact_radius = 0.1` m (existing thickness)

`soft_body_self_position_projection` only works with self contacts.
It is independent of inter-body soft-soft collision modes. Enabling it
does not disable the existing friction and normal-velocity impulses.
All old projects retain their previous behavior by default.

## Derivation

For a vertex at `p` and a triangle at `a,b,c` with closest-point
barycentric weights `u,v,w`, let the contact constraint be

`C = |p - (ua + vb + wc)| - radius` (active when C < 0).

The gradients along the outward normal n are `[+1, -u, -v, -w]`.

For two edges with closest-point interpolation `s,t`, the contact
gradients are `[-(1-s), -s, +(1-t), +t]`, from the first edge to
the second. The **same** code handles both contact types.

With inverse masses `w_i` and compliance `c`, define

`alpha = c / (dt*dt)`
`delta_lambda = -C / (sum_i(w_i * gradient_i^2) + alpha)`
`delta_x_i = w_i * gradient_i * delta_lambda * n`

This is a single pass of the XPBD compliant scalar-contact update
with lambda initially zero, not a persistent constraint multiplier.

The normal and contact thickness use the exact existing narrowphase;
the same direct-neighbor / one-ring topology exclusion remains in effect.
Fully pinned contacts are rejected. No move occurs with compliance/step
invalid, zero contact depth, degenerate normals, or zero effective mass.

## Stable Jacobi accumulation

1. Before querying BVH, allocate or reuse one vector of zero
   displacements, sized to the current soft vertex count.
2. Charge 2 * vertex_count units from the existing per-space VF budget
   for clearing and applying these displacements (no extra global budget).
   Skip positional projection on meshes with more than 4096 vertices.
3. Both VF and EE solvers append position deltas to the vector, without
   changing the vertices' positions while the collision BVHs and AABBs
   are in use. Contact checks still debit their existing budgets.
4. Each individual contact's delta_lambda is capped so no participant
   moves more than `max_correction` for that contact.
5. After **both** contact passes finish, take the maximum length among
   all accumulated displacements and scale **every vertex by the same
   factor** to enforce max per-particle correction. This preserves the
   mass-weighted center of mass of equal-and-opposite internal updates
   (unlike clipping each particle separately).
6. Update both Jolt `mPosition` and `mPreviousPosition` by the same
   amount. This avoids injecting fictitious velocity into Jolt's
   subsequent XPBD integration and leaves pinned particles unchanged.

The order of particles/contacts and finite work budget still matters:
this is an experimental, single-pass nonlinear contact approximation.

## Limitations and follow-up

- Not mathematically complete XPBD, FEM, contact manifold warm-starting,
  or a guarantee against fast self-intersection/tunneling.
- Inextensible cloth springs and contact projection are not solved
  simultaneously. Strong contacts may partially relax when Jolt runs
  subsequent native constraints. Apply a small max correction (e.g.
  0.01–0.02 m) and benchmark under load.
- AABB/candidate lists are built against positions at the start of the
  self collision pass. Delayed Jacobi application deliberately avoids
  invalidating them mid-query.
- Large/dense meshes can exhaust the shared work quota before all
  contacts are processed; motion may be order dependent.
- Additional O(N) buffers and work are allocated/charged **only** when
  the option is on. The prior per-body persistent BVH cache remains
  separately controllable.
- Native C++ compilation, headless scenario, FPS and RAM must be
  validated before enabling by default.

## Regressions

Independent source / analytic math:

    python3 -m unittest tests/stress/test_jolt_soft_self_position_projection.py -v

Native Cgame Jolt regression:

    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
      --path tests/stress/jolt_soft_self_position \
      --script res://position_projection_regression.gd

The native fixture has two stacked disconnected triangles in one soft
body, a crossed-edge body, and a connected quad. **Velocity bias = 0**,
friction = 0 and gravity = 0, so the old velocity-only self-contact solver
cannot separate the initially stationary layers; only a positional
correction can do so. The fixture additionally checks finite coordinates,
stable pinned corners and the unchanged connected-quad control.
