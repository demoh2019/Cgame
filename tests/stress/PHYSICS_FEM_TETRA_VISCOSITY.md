# Opt-in objective volumetric viscoelasticity for SoftBody3D FEM

Cgame's built-in **Godot Physics 3D** backend now supports an experimental
finite-strain *Kelvin–Voigt-like* velocity damping pass for the existing
volumetric Neo-Hookean tetrahedral elements. It models dissipative
deformation without uniformly slowing a flying or spinning body.

The six symmetric material strain-rate modes are derived from the rate
of the Green–Lagrange tensor:

`E=(FᵀF-I)/2`, `dE/dt=(FᵀFdot+FdotᵀF)/2`.

Unlike earlier link damping, it attenuates longitudinal, transverse/shear,
and volumetric strain rates. In exact arithmetic, pure rigid translation
and rotation have no material strain rate. Per-mode mass-weighted velocity
impulses preserve linear **and angular** momentum for freely moving
vertices; each projection is bounded to never reverse its own velocity
mode. The implementation performs all six projections in double and
commits four output velocities atomically.

This is **not** an exact implicit finite-deformation Kelvin–Voigt
constitutive integration; rather, it is an objective, stable
velocity-constraint approximation to a material dashpot.

## Configuration

Under `physics/3d/solver`:

- `soft_body_tetra_fem_compliance > 0`: enable existing Neo-Hookean
  tetrahedral FEM (required). For now, supported on validated closed,
  convex surface meshes with a tetrahedral fan.
- `soft_body_tetra_fem_damping_rate`: new optional positive rate (1/s),
  default **0**. Zero bypasses the O(tetrahedra) pass entirely.
- `soft_body_tetra_fem_poisson_ratio`: existing elastic ratio, unchanged.

For fixed strain rate, the per-physics-frame damping fraction is
`1-exp(-rate*delta)`, giving a step-size-independent fraction under
steady deformation. Run the new pass **before** the position predictor
and nonlinear material constraints, since the local solver later
reconstructs velocity from corrected positions.

### Physical invariants and resource use

- Rest-state rigid rotation/translation: unchanged internal velocities.
- Deformation/shear rates: reduced without increasing kinetic energy
  in exact arithmetic; real_t output checked for finite values and
  excessive kinetic-energy increase.
- Free particles: conserve total linear and angular momentum in the
  mass-weighted model. Pins have zero inverse mass and remain unchanged.
- No extra per-tetra persistent state, lambdas or dynamic allocations.
  Existing FEM rest matrices are reused.

## Tests and limitations

- `tests/servers/test_physics_fem_tetra_viscosity.cpp`:
  7 native Doctest cases including shear/volume dissipation, pins,
  inversion, invalid settings and rigid motion.
- `tests/stress/test_physics_fem_tetra_viscosity.py`:
  5,000 independent seeded numerical reference cases with one in five
  testing simultaneous linear/angular rigid motion; source wiring checks.
- `.github/workflows/physics-fem-tetra-viscosity.yml`:
  Python contracts for PR and develop changes.

This damping is a **heuristic per-mode velocity projection**, not full
Maxwell rheology, strain history, fracture or a complete thermoviscoelastic
continuum model. It operates only when tetrahedralization succeeds and
FEM elasticity is enabled. Non-convex meshes and arbitrary tetrahedral
imports remain unsupported in the current Cgame tetra cooker.
Production use requires full C++ builds, on-engine scene regression,
comparison across time steps, and CPU/RSS benchmarks.
