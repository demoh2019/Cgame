# Generalized Maxwell / three-arm Prony viscoelastic spectrum

Cgame's built-in GodotPhysics3D SoftBody3D tetrahedral FEM solver now
supports up to **three transient Maxwell arms** in parallel with its
existing equilibrium hyperelastic spring. The first arm is the existing
Standard Linear Solid (SLS) from the previous implementation. **Two
optional new arms** let a single soft body combine a very fast and a slow
stress relaxation process. This approximates the generalized Maxwell
rheology and discrete Prony relaxation series found in FEBio and FrontISTR.

## Project Settings (example)

```ini
physics/3d/solver/soft_body_tetra_fem_compliance = 0.00001
physics/3d/solver/soft_body_tetra_sls_compliance = 0.00006
physics/3d/solver/soft_body_tetra_sls_relaxation_time = 0.25
physics/3d/solver/soft_body_tetra_prony_fast_compliance = 0.000015
physics/3d/solver/soft_body_tetra_prony_fast_relaxation_time = 0.04
physics/3d/solver/soft_body_tetra_prony_slow_compliance = 0.00008
physics/3d/solver/soft_body_tetra_prony_slow_relaxation_time = 2.0
```

All **four new settings default to OFF/neutral**: fast and slow
compliances 0, times default 0.04 and 2.0 seconds. A disabled new arm
has no memory update and no spring force, regardless of its time.
Positive FEM compliance is required (equilibrium spring).

If both extra arm compliances remain zero, Cgame uses precisely its
previous single-arm SLS path: no change in equations, no new memory
allocation, and no Prony numerical kernel work.

## Finite-strain formulation

Each cooked tetrahedron has material-frame deformation
`F=Ds*inv(Dm)` with objective Green–Lagrange strain
`E=(F^T*F-I)/2`. Every Maxwell branch independently stores a
symmetric material-frame viscous strain tensor `H_i`:

```text
H_i,next = exp(-dt/tau_i) * H_i + (1-exp(-dt/tau_i)) * E(predicted)
A_i = E - H_i
W_i = V0 * [mu * (A_i:A_i) + lambda/2*tr(A_i)^2]
W_total = sum_i (W_i / compliance_i)
P_total = sum_i [F*(2mu*A_i + lambda tr(A_i)*I) / compliance_i]
C = sqrt(2 W_total)
XPBD_alpha = 1/(dt^2)
```

`mu=1/(2(1+nu))` and
`lambda=nu/((1+nu)(1-2nu))`. Each arm has its own time
constant and inverse-compliance modulus; the base hyperelastic
material retains its separate stiffness and solver.

The shared XPBD projection uses the exact summed analytic first-Piola
gradients. This is **not** equivalent to applying two constraints
sequentially in an arbitrary order. The multi-arm constraint is
backtracked against both inversion and *increased total stored energy*.

All material memories advance once per physics tick, before XPBD
constraint iterations. The **single combined multiplier resets each
physics tick**. Memory survives across frames and resets when the FEM
rest mesh is rebuilt. Pinned nodes and all three equilibrium
hyperelastic materials (Neo-Hookean, Mooney–Rivlin, Ogden) work
without changing their existing numerical kernels.

Optional irreversible scalar FEM damage lowers transient branch
stiffness as `compliance_i/(1-damage)`, consistent with the existing
one-arm SLS and other local tetra material constraints.

## Limitations

This is a **finite-Green-strain multi-arm Maxwell approximation**, not
a calibrated quasi-linear viscoelastic law, thermorheologically simple
polymer model, dynamic crack propagation, or general six-term Prony
series. The exact relaxation modulus under small step strain has the
expected multi-exponential form; behavior at high strain follows the
chosen Green-strain branch approximation. Plastic rest-matrix changes
can affect interpretation of saved viscous strain, and require
calibration/regression with strong viscoplasticity enabled.

The model adds O(active Maxwell branches × tetrahedra × XPBD iterations)
work, but no work when both new compliances are zero. Existing
explicit tetrahedral meshes with interior nodes are supported if
the built-in FEM cooker validates them.

## Validation

- `tests/servers/test_physics_fem_tetra_prony.cpp`: 16 native C++ tests
  for additive energy and stress, fast/slow exponential relaxation,
  single-arm SLS equivalence, rigid-rotation objectivity, exact nodal
  gradient finite differences, timestep subdivision, inverted tets,
  pinned vertices, invalid/atomic memory updates, rest winding.
- `tests/stress/test_physics_fem_tetra_prony_compiler.cpp`: compile and
  execute the real C++ production FEM header under float/double.
- `.github/workflows/physics-fem-prony.yml`: smoke CI for PR/develop.
- Full Godot native build and full-scene performance/stability tests
  remain necessary before considering this production ready.

## Engine comparisons

- [FEBio Viscoelasticity](https://febiosoftware.github.io/febio-docs/theory/chapter5/5.4-viscoelasticity/)
  explains discrete Prony exponential relaxation spectra.
- [FrontISTR generalized Maxwell](https://docs.frontistr.com/en/theory/constitutive/04_viscoelastic.html)
  describes the parallel relaxation arms and internal variables.
