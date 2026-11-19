# Experimental finite-strain deviatoric plasticity — tetra FEM

Cgame's Godot Physics 3D backend has Neo-Hookean, Mooney–Rivlin and
Ogden elastic FEM, optional viscosity, volume plastic creep, material
fiber remodeling and scalar damage. The remaining missing fundamental
plastic mode is **isochoric shape change** under tensile/shear stresses.

This experimental module introduces *Hencky-logarithmic deviatoric
plastic rest remodeling* on each FEM tetrahedron. The model is inspired
by the split into volumetric and deviatoric stresses and radial-return
plasticity described in Sandia's J2 plasticity literature and by the
local tetrahedral constraint structure in PositionBasedDynamics.
No external engine source was copied.

## Configuration

Under `physics/3d/solver`:

- `soft_body_tetra_fem_compliance > 0`: required existing elastic FEM
- `soft_body_tetra_deviatoric_plastic_rate`: default **0**, disabled;
  positive means the logarithmic shear yield mode creeps (1/s)
- `soft_body_tetra_deviatoric_plastic_yield`: default **0.12**; elastic
  equivalent logarithmic strain threshold
- `soft_body_tetra_deviatoric_plastic_hardening`: default **0.2**;
  dimensionless hardening per unit accumulated equivalent plastic strain
- `soft_body_tetra_deviatoric_plastic_max_strain`: default **3.0**;
  cap on accumulated plastic equivalent strain, valid (0,8]

This mode works with the existing convex-tetra cooker or explicitly
provided validated tetrahedral connectivity. It runs only in the
built-in Godot Physics 3D backend, not Jolt.

## Material mathematics

Compute `F=Ds*inverse(Dm_plastic)` from current predicted vertex
positions and the persistent inverse rest matrix. Form the symmetric
right Cauchy–Green matrix `C=F^T F`, diagonalize via bounded Jacobi
sweeps and obtain principal Hencky strains `e_i=log(sigma_i)`.

Subtract their mean to isolate isochoric logarithmic stretches:

```
dev_i = e_i - mean(e)
eq = sqrt(2/3 * sum(dev_i^2))
yield_effective = yield_0 + hardening * accumulated_plastic_strain
```

Compute a hardening-aware exponential relaxation factor once per
physics tick:

```
relaxation = (1 - exp(-rate * dt * (1 + hardening))) / (1 + hardening)
increment = clamp((eq - yield_effective) * relaxation,
                  0, eq, max_accumulated - accumulated)
beta = increment / eq
S = eigenvectors * diag(exp(-beta*dev_i)) * eigenvectors^T
inverse(Dm_plastic)_new = S * inverse(Dm_plastic)_old
```

Since `sum(dev_i)=0`, `det(S)=1`: **tetra reference volume and
conserved nodal masses stay constant**. The *shape* of the rest metric
changes irreversibly. Separate isotropic volumetric plasticity
continues to handle expansion and compression.

Plastic flow happens exactly once per physics step **before** the
elastic XPBD iterations. The algorithm uses cached FEM rest matrices
and a single optional accumulated-shear scalar per tetra, lazily
allocated. Matrix eigen decomposition and updates use stack-local
double precision only. Singular/inverted elements, invalid matrices
and catastrophic conditioning are rejected transactionally. Each
update renormalizes the rest inverse determinant to control drift.

### Scope

This is a **logarithmic-strain radial-relaxation approximation**, not
a rigorously calibrated stress-based multiplicative J2 plastic model.
No plastic spin, thermal state, anisotropic yield surface, fracture,
or topology splitting is implemented. The existing collision mesh,
gas reference, nodal masses and explicit tetra connectivity are
unchanged. If the creep rate is turned off, existing plastic rest
deformation remains, but the plastic update pass is skipped.
The accumulated strain history persists until mesh reconstruction.

## Validation

- `tests/servers/test_physics_fem_tetra_deviatoric_plasticity.cpp`:
  7 native Doctest cases for permanent isochoric deformation, rigid
  rotations, uniform volume deformation, hardening, strain caps,
  composition with volumetric plasticity and finite/inversion guards
- `tests/stress/test_physics_fem_tetra_deviatoric_plasticity.py`:
  8,000 seeded independent reference cases: material isochoric volume
  preservation, rotation invariance and rate-splitting invariance
- `.github/workflows/physics-fem-deviatoric-plasticity.yml`:
  focused Python regression CI.

The reference models and source checks are not substitutes for a
native C++ engine build, scenes testing complex tetra connectivity,
time-step convergence under coupled contact forces or CPU/RSS
benchmarks. This is opt-in experimental physics.
