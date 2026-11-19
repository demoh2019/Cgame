# Third volumetric FEM material: one-term Ogden (principal stretches)

Cgame now supports an opt-in **one-term Ogden** compressible hyperelastic
constitutive model for the existing validated convex tetrahedral SoftBody3D
mesh. The previous Neo-Hookean and Mooney–Rivlin options remain available
and unchanged by default.

The model follows the general isotropic principal-stretch Ogden family
documented by SOFA's TetrahedronHyperelasticityFEMForceField and FEBio's
solid-material theory. This implementation has its own explicit quadratic
volumetric penalty and unit-Young-modulus normalization, so its parameters
are **not** numerically interchangeable with another library's Ogden
parameters without calibration.

## Project settings

```ini
physics/3d/solver/soft_body_tetra_fem_compliance = 0.00001
physics/3d/solver/soft_body_tetra_fem_poisson_ratio = 0.3
physics/3d/solver/soft_body_tetra_fem_material_model = 2
physics/3d/solver/soft_body_tetra_ogden_exponent = 3.0
```

Material model enum:

- `0` (default): original Neo-Hookean
- `1`: compressible Mooney–Rivlin with existing invariant split setting
- `2`: one-term Ogden, parameter `alpha = 1..8`

When `alpha=2`, the Ogden strain energy matches the *isochoric first
invariant* Mooney–Rivlin branch (`fraction=0`) in Cgame, not the original
compressible Neo-Hookean formulation.

## Numerical formulation

For `F = Ds * inverse(Dm)`, let `J = det(F) > 0` and let
`sigma_1, sigma_2, sigma_3 > 0` be the principal stretches from
the eigenvalues of `C=F^T F`. With `E=1` normalized material stiffness,
`mu=1/(2*(1+nu))`, `K=1/(3*(1-2*nu))`, `1 <= alpha <= 8`:

```text
S = sigma_1^alpha + sigma_2^alpha + sigma_3^alpha
W = (2*mu/alpha^2) * (J^(-alpha/3) * S - 3)
    + (K/2)*(J-1)^2

Q = sum_i sigma_i^(alpha-2) v_i v_i^T
P = (2*mu/alpha)*J^(-alpha/3)*(F*Q - S/3 * F^-T)
    + K*(J-1)*cof(F)
```

`v_i` are the eigenvectors of `C`, derived using a deterministic cyclic
Jacobi symmetric 3x3 eigensolver with **double** intermediates. This
spectral gradient is continuous for coincident principal stretches, because
the matrix function `Q` does not divide by differences between eigenvalues.
No singular-value-dependent allocations or cached topology changes.

The 4 nodal energy gradients are computed by applying `P` to the
tetrahedron's rest inverse edge matrix, then the existing XPBD energy
constraint solver updates positions with the same compliance, per-element
multiplier and anti-inversion backtracking as the previous materials.

## Interaction with other systems

- Reuses the current convex multi-tet cooker and volume-lumped masses.
- Preserves the optional inversion-recovery pass before the Ogden solver.
- Scalar **irreversible damage** reads the selected Ogden energy, not
  Neo-Hookean energy, to maintain consistent strain thresholds.
- Existing fiber reinforcement (including damaged-fiber softening),
  Kelvin–Voigt material viscosity and surface constraints stay independent.
- The new material does not split the collision mesh or generate fractures.

## Validation

- `tests/servers/test_physics_fem_tetra_ogden.cpp`: 13 native C++ unit
  cases, including rest, rigid rotation, material matching at order 2,
  gradient finite differences, shear/compression, pinned vertices, winding,
  degenerate/inverted states, repeated eigenvalues and compliance.
- `tests/stress/test_physics_fem_tetra_ogden_compiler.cpp`: independent
  native production-header compile/runtime smoke under float32/float64.
- `.github/workflows/physics-fem-ogden.yml`: dedicated CI contract.

Independent Python numerical checks during development: 300 random
deformation gradients with maximum analytic-vs-numerical stress derivative
error ~6.7e-10; 2,000 random symmetric spectra with maximum eigenmatrix
function discrepancy ~2.5e-14. These are **not** a replacement for a
full-engine build or native C++ testing.

## Sources

- SOFA hyperelastic tetra FEM material options:
  https://sofa-framework.github.io/doc/components/solidmechanics/fem/hyperelastic/tetrahedronhyperelasticityfemforcefield/
- FEBio Ogden constitutive theory:
  https://febiosoftware.github.io/febio-docs/features/features/solid_material_ogden/
