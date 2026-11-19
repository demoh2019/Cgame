# Finite-strain Standard Linear Solid branch for volumetric FEM

The built-in GodotPhysics3D SoftBody3D tetrahedral FEM system supports an
**optional one-arm Standard Linear Solid (Zener) viscoelastic branch** in
parallel with its existing equilibrium Neo-Hookean, Mooney–Rivlin or
Ogden material. Unlike the pre-existing instantaneous Kelvin–Voigt
strain-rate damping, this mode remembers the past deformation and relaxes
a transient extra stress over a user-controlled physical time constant.

The implementation takes inspiration from the [SOFA viscoelasticity
plugin](https://www.sofa-framework.org/applications/plugins/visco-elasticity/),
which supports Maxwell, Kelvin–Voigt and Standard Linear Solid laws for
tetrahedral deformable meshes. This Cgame feature is an original
**experimental finite-Green-strain SLS approximation**, not a code port,
multi-branch Prony series, or a calibrated polymer material model.

## Configuration

```ini
physics/3d/solver/soft_body_tetra_fem_compliance = 0.00001
physics/3d/solver/soft_body_tetra_sls_compliance = 0.00005
physics/3d/solver/soft_body_tetra_sls_relaxation_time = 0.25
```

- `soft_body_tetra_sls_compliance`: default 0, disables SLS and all
  associated per-tetra memory and solver work. Positive values turn on
  the additional transient stiffness. Requires positive **base FEM**
  compliance to maintain equilibrium elasticity.
- `soft_body_tetra_sls_relaxation_time`: default 0.25 **seconds**;
  clamped to a small strictly positive lower bound for numerical safety.
- Poisson ratio comes from the existing
  `soft_body_tetra_fem_poisson_ratio` property.

## Model

For each tetrahedron, use its existing rest matrix `Dm` and current
position edges `Ds`. Compute `F = Ds * inverse(Dm)`, then the objective
Green–Lagrange strain `E=(F^T F-I)/2`. The transient Maxwell arm stores a
symmetric tensor `H` in the rest material frame:

```text
H(t+dt) = exp(-dt/tau)*H(t) + (1-exp(-dt/tau))*E(predicted)
A = E - H
W_transient = V0 * [mu * (A:A) + lambda/2 * trace(A)^2]
P_transient = F * [2mu*A + lambda*trace(A)*I]
```

`mu=1/[2*(1+nu)]` and
`lambda=nu/[(1+nu)*(1-2nu)]` for unit Young modulus. The local
XPBD energy constraint is `C=sqrt(2*W_transient)`, and
`alpha = sls_compliance/dt²`. Four analytic nodal derivatives of the
transient energy are used. Corrections are backtracked to avoid
tetrahedron inversion; pinned nodes have zero inverse mass.

The memory advances **exactly once per physics tick**, on predicted
positions and before solver iterations. It stays unchanged throughout
all iterations in that tick. Its XPBD multiplier resets at the beginning
of the new tick. Under a fixed deformation, transient extra energy
decays as `exp(-2*dt/tau)`; after unloading, the internal strain memory
produces a temporary reverse restoring stress before relaxing back
to zero. Rigid translations and rotations do not alter Green strain.

## Integration and caveats

- This adds **transient viscoelastic stress**, not a replacement of
  any one of the three existing nonlinear hyperelastic models.
- Uses the same cooked tetrahedra as explicit/convex imported meshes,
  volume-lumped masses, inversion recovery and fiber reinforcement.
- Existing irreversible damage scales SLS transient compliance in the
  same way as other material constraints.
- Per-tetra volume/shear plasticity changes rest metrics, and thus can
  affect SLS internal memory interpretation. Avoid calibrating strong
  plasticity and strong SLS simultaneously without additional validation.
- No thermal coupling, multi-term relaxation spectra, active fluid mesh
  deformation, fracture topology or material calibration.
- Numerical stiffness and convergence depend on the SLS compliance and
  the built-in XPBD iteration/substep settings.

## Tests

- `tests/servers/test_physics_fem_tetra_standard_linear_solid.cpp`:
  14 native doctest cases including rigid objectivity, exact exponential
  creep, unloading memory, shear tensor symmetry, energy/force analytic
  finite differences, pinning, compliance and inversion handling.
- `tests/stress/test_physics_fem_tetra_standard_linear_solid_compiler.cpp`:
  independent native C++ header smoke in float and double.
- `.github/workflows/physics-fem-standard-linear-solid.yml`:
  pull-request and develop CI smoke contract.

Full Godot engine build and full-scene stress regression remain required
before production deployment.
