# Godot Physics 3D — Continuous vertex/triangle SoftBody pair contacts

Experimental linear-motion **soft-soft CCD** extends the current discrete,
two-way vertex–face XPBD solver. Inspired by rigid-body shape casting in
Jolt Physics and Bullet's deformable collision pipeline, it is opt-in and
does not modify the Jolt backend.

## Configuration

Under `physics/3d/solver`:

- `soft_body_pair_collision_thickness` must be **positive** to enable pair
  contacts (still defaults to `0`).
- `soft_body_pair_collision_ccd` — **false** by default. Set true to
  preserve previous positions and detect within-step vertex/face crossings.
- Existing `soft_body_pair_collision_compliance`, `...friction`,
  `soft_body_pair_max_pairs` and `soft_body_pair_max_contacts` apply
  unchanged to the normal/discrete contacts.

## Implementation

Each active SoftBody3D saves one previous position per node **only if both
pair contacts and CCD are enabled**. Node::q cannot be used after local
constraint projection, because that value is overwritten during
velocity reconstruction. The previous-position array is reset when CCD is
disabled; the default mode has no extra per-node memory.

At the end of each local solve, compute a swept body AABB enclosing each
particle's start and final positions. The pair-level body-AABB culling
uses swept bounds in CCD mode, so high-speed objects that no longer overlap
at frame end are still considered. Before candidate enumeration, the
existing triangle BVH is conservatively refitted to the union of each
triangle's start/end positions; vertex queries use their swept AABB.
No second persistent BVH is allocated.

The narrowphase uses the existing
`physics_xpbd_swept_vertex_triangle()` cubic plane-root bracketing and
barycentric containment tests to determine the first transverse crossing
of the moving vertex and linearly moving triangle. Crossing contacts are
processed before current-position contacts so the original collision
side is not lost. Separate bounded scratch vectors keep discrete contacts
compact.

The time-of-impact witness and signed normal feed
`physics_xpbd_solve_swept_vertex_face()`. A new wrapper applies the
resulting positional corrections to both soft bodies' velocities using
`delta_position / dt`. All four particle positions, velocities, and the
XPBD multiplier are committed atomically after finite checks. Pins (zero
inverse mass) remain fixed.

Existing contact/per-vertex and pair budgets remain in force. Swept
contacts intentionally skip the discrete Coulomb friction stage: friction
for a swept witness needs dedicated TOI contact-frame modeling.

## Validation and limitations

- `tests/servers/test_physics_softbody_pair_ccd.cpp`: native C++ tests for
  crossing vertex vs pinned triangle, moving face vs pinned vertex,
  mass-weighted momentum, missed/grazing contacts and invalid values.
- `tests/stress/test_physics_softbody_pair_ccd.py`: 3,000 seeded moving
  planar contact cases with TOI, momentum, pinning, conservative swept AABBs,
  and runtime source wiring.
- `.github/workflows/physics-softbody-pair-ccd.yml` runs Python contracts
  for PRs and develop changes.

This is **vertex–triangle linear-motion CCD**, not a complete continuous
deformable collision system. It does not detect edge–edge crossings,
coplanar/tangential/grazing events or all rotating/deforming mesh topologies.
No global time rewind or continuous substepping is performed. Very large
corrections can be disruptive; compare with dense 120-Hz substeps, test
fast crossing cloth and soft balls, pins and compound scenes, and measure
frame time/RSS before enabling for shipped games.

Native C++ engine compilation and live scene simulation are required for
production validation, beyond the Python reference tests.
