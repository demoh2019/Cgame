# SoftBody3D angular damping (XPBD cloth)

This change adds a separate viscous **dihedral-bending damping** mode to
Cgame's Godot Physics 3D backend. The purpose is to dissipate fast folding
oscillations without indiscriminately slowing rigid translations/rotations.
It complements the existing link-axis damping, XPBD dihedral elasticity,
and optional permanent-bend plasticity.

## Configuring the solver

Two project settings are relevant:

- `physics/3d/solver/soft_body_xpbd_dihedral_compliance` must be **positive**
  for the mesh to build its adjacent-triangle hinge list.
- `physics/3d/solver/soft_body_dihedral_damping` is the angular relaxation
  rate in **1/s** (default **0**, disabled).

The damping parameter is cached per physics space. The per-step removed
fraction is `1 - exp(-rate * dt)`. The pass executes after longitudinal
link damping but before `node.x = node.q + node.v * dt` and XPBD
position projections. Thus it changes the motion being integrated, rather
than a velocity that would be overwritten by end-of-step reconstruction.

## Physical model

For four particles around an oriented hinge, let `J_i` be the gradient of
the **signed dihedral angle** with respect to particle `i`. Define:

- Angular rate: `qdot = sum_i dot(J_i, v_i)`.
- Inverse effective mass: `W = sum_i (inv_mass_i * dot(J_i, J_i))`.
- Impulse: `lambda = -(1 - exp(-rate*dt)) * qdot / W`.
- Update each velocity: `v_i += inv_mass_i * J_i * lambda`.

The impulse leaves velocities unchanged along rigid-body translation and
rotation modes. With nonnegative inverse masses and a damping fraction in
[0,1], it cannot add kinetic energy in exact arithmetic. Pins (inverse
mass zero) remain fixed; reaction forces at pinned vertices come from the
external attachment. Computation is O(hinges), requires no persistent new
buffers, and uses double-precision reductions with transactional finite
checks. Degenerate hinges are skipped.

## Checks

- `tests/servers/test_physics_softbody_dihedral_damping.cpp`: Godot-native
  Doctest tests for complete/partial damping, rigid motion, pins,
  momentum, kinetic energy, timestep subdivision, signed-angle finite
  difference, and invalid input.
- `tests/stress/test_physics_softbody_dihedral_damping.py`: deterministic
  2,000-case numerical reference stress check, finite-difference Jacobian
  checks, and source/configuration wiring checks. Runs in CI.
- `.github/workflows/physics-softbody-dihedral-damping.yml`: PR and develop
  CI workflow for the Python reference-level contracts.

For a full local C++ validation, build Godot with SCons `tests=yes` then
run its headless Doctest runner for `[PhysicsDihedralDamping]`. Also
compare an animated cloth corner, rigidly translating cloth, and dense
cloth under damping rates 0, 2 and 20 s^-1 to measure frame time and
peak RSS. Test both float32 and float64 engine configurations.

## Scope and limitations

This improves cloth and thin-shell **angular damping**; it is not a
replacement for tetrahedral FEM, plasticity, or true soft-soft contact.
The Jolt Physics backend is unchanged. The implementation is opt-in and
uses the already existing XPBD hinge topology; if dihedral compliance is
disabled, no hinge list is built and angular damping is inert.

The Python contract suite is not a complete Godot engine build, and does
not measure scene-level performance.
