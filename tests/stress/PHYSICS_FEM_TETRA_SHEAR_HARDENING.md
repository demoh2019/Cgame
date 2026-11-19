# Isochoric tetra FEM plastic work hardening

The existing Godot Physics 3D tetrahedral FEM solver contains
Neo-Hookean, Mooney-Rivlin and Ogden elasticity, scalar damage,
volumetric plastic creep, and J2-like Hencky deviatoric plasticity.
This extension adds **isotropic yield surface hardening** to the
existing deviatoric solver, not a competing plastic solver.

Related reference: Sandia's J2 radial return algorithm separates
hydrostatic and deviatoric stresses and varies yield stress with
accumulated plastic strain; this feature is a simpler strain-space
approximation inspired by the same hardening idea.

## Configuration

Under `physics/3d/solver`:

- `soft_body_tetra_fem_compliance > 0` enables FEM (required).
- `soft_body_tetra_shear_plastic_rate > 0` enables pre-existing shear
  plasticity and its per-tetra cumulative plastic state (required).
- `soft_body_tetra_shear_plastic_yield` original equivalent
  logarithmic strain threshold, default **0.2**.
- **NEW:** `soft_body_tetra_shear_plastic_hardening`, default **0**,
  valid range [0,10]. Zero preserves the original flow law.
- `soft_body_tetra_shear_plastic_max_strain`, original cumulative cap,
  default **2.0**.

Only Godot Physics 3D (not Jolt). Existing explicit/convex tetrahedral
mesh cooking, mass, pins and surface contacts are unchanged.

## Material law

For the right stretch U of the current deformation gradient,
its 3 principal logarithmic strains `e_i=log(sigma_i)` produce a
deviatoric equivalent norm:

```
dev_i = e_i - mean(e)
eq = sqrt(2/3 * sum(dev_i^2))
yield_current = yield_initial + H * accumulated_plastic_shear
relaxation = (1-exp(-rate*dt*(1+H)))/(1+H)
increment = min(max_plastic-accumulated,
                relaxation*max(0,eq-yield_current))
```

This formula exponentially integrates the strain-space rate law at
constant imposed Hencky deformation, and automatically slows
plastic creep as the material work-hardens.

The plastic metric change is unchanged: principal stretch
correction `exp(-increment*dev_i/eq)` updates the existing inverse
rest tetra matrix while preserving its reference volume. New
guards renormalize its determinant to avoid slow isochoric drift
after many plastic steps. All rest matrix and accumulated history
mutations are atomic. Malformed/inverted inputs do not commit.

No new per-tetra buffers: the existing `plastic_deviatoric_strain`
history in each cooked tetrahedron is reused. Default hardening=0
is mathematically backward-compatible.

## Validation

- `tests/servers/test_physics_fem_tetra_shear_hardening.cpp`: 6 native
  C++ cases for hardening, yield expansion, time-substep consistency,
  skew reference tetrahedra, composition with volume plasticity,
  invalid input and backward compatibility.
- `tests/stress/test_physics_fem_tetra_shear_hardening.py`: 9,000
  seeded reference cases with rate/strain/volume invariants plus
  source-wiring regression checks.
- `.github/workflows/physics-fem-shear-hardening.yml`:
  focused Python CI workflow.

This is a phenomenological **Hencky-strain** hardening model, not an
exact stress-based multiplicative J2 return mapping; real fracture
and thermal plasticity remain separate future features. Complete
C++ compilation, full simulation scenes and resource benchmarks are
required before production use.
