# Cgame / Jolt — speculative CCD for nonadjacent edges inside ONE soft body

## Why add this?

Jolt Physics still documents soft-versus-soft contacts as not implemented
upstream. Bullet has vertex–face / cluster self-collision modes (CL_SELF),
and deformable engines distinguish discrete contacts from continuous
collision detection (CCD). Earlier Cgame opt-in self contact modes solve
vertex–triangle and edge–edge overlap, but an edge moving through another
edge within one fixed time step might leave neither pair overlapping at
the start or end of the frame.

This feature adds a **bounded linearized conservative-advancement sweep**
for **self edge–edge** contacts. It deliberately reuses Cgame's existing
soft/soft edge sweep helper; no external physics-engine source is copied.

## Enable

Under `physics/jolt_physics_3d/simulation/`:

- `soft_body_self_contacts=true` (existing self-collision master)
- `soft_body_self_edge_contacts=true` (existing discrete EE)
- `soft_body_self_speculative_edge_ccd=true` (**new**, default false)
- `soft_body_soft_ccd_max_sweep=1.0` m (existing 0..4 m)
- `soft_body_soft_ccd_max_correction_speed=128.0` m/s (existing 1..256)
- `soft_body_soft_contact_radius=0.1` m (existing)
- `soft_body_self_contact_max_checks=16384` (existing global cap)

Does not require cross-body `soft_body_soft_contacts`. Self positional
Jacobi correction is a separate setting and is **not** applied to
predicted future contacts.

## Algorithm

1. Use existing one-ring mesh connectivity and reject any edge pair
   sharing a vertex or with endpoints connected by a triangle edge.
   Pairs are unordered (`j > i`) and exactly tested once.
2. The existing self-edge BVH can be built/refitted in the original
   *current* particle positions. Its node/edge queries and the linear
   fallback expand the AABB by `contact_radius + max_sweep` only while
   speculative self EE is enabled. No new tree format, scratch memory
   or per-step construction is required.
3. Use the original exact clamped segment nearest-point test. Any
   pair already overlapping at the present step is handled by the
   old discrete solver, unchanged.
4. For a currently separated candidate, evaluate the four endpoint
   velocity differences and compute their maximum magnitude. The
   distance between linearly moving segments is Lipschitz-continuous
   with this upper relative-speed bound. Reject any pair whose
   `speed_bound * dt` exceeds the configured `max_sweep`.
5. Repeatedly advance time by `(distance - radius) / speed_bound`,
   recomputing closest segment points until touching or exceeding
   the frame. Maximum **16** iterations, each additionally charged to
   the current shared self-edge CPU work quota.
6. Interpolate endpoint velocity at the predicted contact parameters
   `s,t`; accept only *approaching* contact normals. Apply the
   existing equal-and-opposite, inverse-mass-weighted impulse across
   four endpoints, bounded by the configured CCD correction speed.
   **No penetration bias and no position projection** for a future
   contact. Current overlapping pairs keep their old behavior.
7. Exact Coulomb friction and pinned-particle checks remain in place.

### Why static enlarged BVHs are conservative for accepted sweeps

The solver only allows a predicted pair when the relative maximum
endpoint travel over the frame is <= max_sweep. In every coordinate the
two moving segments' separation can shrink by no more than that
relative travel bound. Therefore if the **current** edge AABBs are
separated by more than `radius + max_sweep` along any axis, the
predictor could not accept their future contact. Expanding BVH and
linear broadphase by that amount avoids false-negative culling without
rebuilding a new swept hierarchy from vertex velocities.

This is intentionally a *conservative broadphase*: large sweep margins
can add many false-positive candidates but cannot exhaust the work cap
without accounting for those tests.

## Limitations

- **Not guaranteed deformable CCD:** actual soft motion can be nonlinear
  under solver constraints, collisions, accelerations and substeps. The
  swept predictor assumes constant endpoint velocities in one frame.
- No time-of-impact rewind, substep interpolation of Jolt's internal
  XPBD constraints, or continuous self vertex-face detection.
- Conservative-advancement iteration cap, maximum sweep, CPU quota and
  zero-speed/degenerate/near-tangential rejection can skip contacts.
- If self-edge BVH is enabled, enlarged candidate queries can reduce
  its culling efficiency. Persistent self BVH stays compatible but
  performance needs real native profiling.
- The self-contact solver is pre-step and order-dependent when many
  overlapping contacts modify particle velocities.
- No FEM, cutting, plasticity, damage propagation or warm-started
  contact manifolds are supplied in this patch.
- As an experimental opt-in, it should not be enabled in production
  before the native C++ build and physical regression/CPU stress pass.

## Tests

Reference math, work-budget, broadphase and source contracts:

    python3 -m unittest tests/stress/test_jolt_soft_self_edge_sweep.py -v

Native Cgame Jolt test:

    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
      --path tests/stress/jolt_soft_self_edge_sweep \
      --script res://swept_self_edges_regression.gd

The scene drives two identical six-vertex soft meshes using point
impulses: one contains a pair of crossing edges, while the control's
second triangle is 3 m away and cannot collide internally. All other
mesh connectivity, masses, pins and driving impulses match. It checks
finite state, pinned vertices and reduced peak travel for the crossing
edge. This is intentionally a *native regression*, not a benchmark.
