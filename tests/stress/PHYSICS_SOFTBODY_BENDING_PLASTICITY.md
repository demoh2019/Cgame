# XPBD soft-body bending plasticity

This opt-in mode adds a **viscoplastic rest-angle update** to the existing
Godot Physics 3D XPBD dihedral hinge solver. It does not modify the Jolt backend.

## Project settings

- `physics/3d/solver/soft_body_xpbd_dihedral_compliance`: must be positive to
  build hinges and activate angular XPBD bending.
- `physics/3d/solver/soft_body_bending_plastic_yield_angle`: allowable elastic
  angular difference in **radians** (default 0.2, clamped to [0, PI]).
- `physics/3d/solver/soft_body_bending_plastic_creep_rate`: rest-angle relaxation
  rate in **1/s** (default 0, disabled).

For a fold exceeding yield, the target rest angle is the closest angular
boundary of the elastic band, taking the shortest angular route across +/-PI.
Per simulation step, the rest angle relaxes toward that target by
`1 - exp(-creep_rate * dt)`. Each hinge is processed once before XPBD
iterations; it is **not** updated on every iteration.

Zero creep adds no hinge traversal, no new allocations and preserves the
previous solver. Only valid manifold hinges accepted by the existing topology
builder are considered.

## Verification

Unit tests in `tests/servers/test_physics_softbody_bending_plasticity.cpp`
cover elastic response, positive and negative yielding, wraparound near PI,
timestep-subdivision consistency at fixed angle, and invalid input handling.

Suggested scene-level cases after a local engine build:

1. Enable dihedral compliance and creep. Pin one edge of a two-triangle
   cloth strip and fold it past the yield angle; after release, it should
   retain part of its fold.
2. Repeat with creep 0; it should recover elastically as before.
3. Flip a hinge across +/-PI; ensure no violent 360-degree correction.
4. Change physics FPS with the same imposed fold and total elapsed time;
   compare the final rest shape.
5. Benchmark a dense cloth in disabled/enabled mode for CPU time and peak RAM.

**Limitations:** The model creates permanent *bending* deformation, not
plastic stretching of tetrahedral volumes. The separate link plasticity
setting continues to control permanent stretch/compression. No build or
scene-level benchmark has been performed by this change.
