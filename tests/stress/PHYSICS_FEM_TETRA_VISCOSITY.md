# Opt-in objective FEM tetrahedral material viscosity

The built-in GodotPhysics3D `SoftBody3D` solver can now apply
**Kelvin–Voigt finite-strain material damping** independently of Neo-Hookean
elastic compliance. The soft body's closed, consistently wound,
**convex** surface is first preprocessed into tetrahedra by
`physics_fem_convex_star.h`.

## Project settings

```ini
physics/3d/solver/soft_body_tetra_fem_compliance = 0.00001
physics/3d/solver/soft_body_tetra_fem_poisson_ratio = 0.3
physics/3d/solver/soft_body_tetra_fem_viscosity = 10.0
```

Viscosity `0` is the default, and performs **no** extra FEM viscosity work or
allocations. It can also be used with FEM elasticity compliance `0` when a
closed convex surface is available. The coefficient is an effective scalar
material viscosity in the normalized internal FEM solver units, **not**
a calibrated SI viscosity. The safest starting point is a small positive
value followed by testing under the project's intended physics tick rate.

## Physical model

Let `F` be the tetrahedron's current deformation gradient and
`F_dot` its time derivative built from relative vertex velocities.
The Green–Lagrange strain-rate tensor is

```text
E_dot = 0.5 * (F^T F_dot + F_dot^T F)
S_viscous = viscosity * (2*mu*E_dot + lambda*trace(E_dot)*I)
P_viscous = F * S_viscous
force_b,c,d = -rest_volume * P_viscous * inv(Dm)^T
force_a = -(force_b + force_c + force_d)
```

Unlike damping individual vertex world velocities, the result vanishes for a
rigid translation and a rigid rotation, even around an already deformed shape.
The resulting impulses conserve total linear momentum for movable vertices
(without kinematic constraints). Inversion and near-zero determinant cause an
atomic no-op. Each element is evaluated without heap allocations.

For explicit viscosity `v_next = v + dt * inv_mass * force`, excessive
viscosity can otherwise inject kinetic energy. The solver clamps `dt` by
the mass-weighted kinetic-energy descent step
`-sum(v·force) / sum(inv_mass * |force|²)` when that bound is finite and
positive. Only movable velocities are updated; pinned vertices stay fixed.

## Validation

`tests/servers/test_physics_fem_tetra_viscosity.cpp`: 12 focused C++ tests
for translation/rotation objectivity, deformed rigid spin, rest/strain,
Poisson coupling, pins, inversion, momentum and high-viscosity energy
safeguards.

`tests/stress/test_physics_fem_tetra_viscosity_compiler.cpp`: a standalone
C++ smoke compiling the **real production header**, run for float32 and
float64 by `.github/workflows/physics-fem-tetra-viscosity.yml`.

This is not a new arbitrary concave tetrahedralization engine, fracture or
a physically calibrated material pipeline. It complements the existing
global breathing-mode bulk viscosity and separate surface-membrane damping.
