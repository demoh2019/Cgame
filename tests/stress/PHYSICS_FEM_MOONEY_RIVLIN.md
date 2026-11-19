# Mooney–Rivlin hyperelastic finite elements for GodotPhysics3D

This adds a second, opt-in 3D volumetric hyperelastic constitutive model to
Cgame. It runs on the **existing cooked tetrahedral mesh** for closed convex
SoftBody3D objects; no new collision mesh, mass system or vertex format.

Unlike the existing compressible Neo-Hookean law (which remains default),
Mooney–Rivlin uses two isochoric material invariants to represent different
nonlinear responses of rubber-like materials at large strain.

## Project Settings

```ini
physics/3d/solver/soft_body_tetra_fem_compliance = 0.00001
physics/3d/solver/soft_body_tetra_fem_poisson_ratio = 0.3
physics/3d/solver/soft_body_tetra_fem_material_model = 1
physics/3d/solver/soft_body_tetra_mooney_rivlin_fraction = 0.5
```

- **Material model 0 (default)**: existing Neo-Hookean equations, with no
  codepath or result change when this feature is not enabled.
- **Material model 1**: compressible isochoric Mooney–Rivlin.
- **Fraction s (0–1)**: `C01/(C10+C01)`. `0` selects only the first
  isochoric invariant *within Mooney–Rivlin*, which is not identical to
  the legacy compressible Neo-Hookean energy.

## Energy model and solver

```text
F = Ds * inv(Dm)                 // deformation gradient
J = det(F) > 0
I1 = tr(F^T F)
I2 = 0.5 * (I1^2 - tr((F^T F)^2))
I1bar = J^(-2/3) * I1
I2bar = J^(-4/3) * I2
mu = 1/(2*(1+nu)), K = 1/(3*(1-2nu))
C10 = mu*(1-s)/2, C01 = mu*s/2
W = C10*(I1bar-3) + C01*(I2bar-3) + K/2*(J-1)^2
```

The production implementation evaluates exact analytical first Piola
stress (energy derivative) and the associated 4 nodal gradients in
double precision. The same inversion-protecting XPBD energy
constraint, compliance and multiplier semantics as Neo-Hookean are used.

Existing opt-in damage computes equivalent strain from **the selected
material's undamaged energy**. Tetrahedral fibers, mass lumping,
Kelvin–Voigt damping, and shape constraints remain independently
configurable. Damping retains its existing material-independent
objective strain-rate formulation.

## Limitations and validation

This is not a claim of complete PhysX/SOFA material support, fracture,
arbitrary concave tetrahedral cooking or a calibrated real-world polymer
model. Extremely large/highly inverted deformations are rejected instead
of being evaluated by a singular material law.

- 12 native C++ tests: rest/rotations, strain, material split sensitivity,
  exact gradient finite differences, pinning, inversion, compliance.
- Independent native compiler smoke with both float32 and float64
  configurations, using the real production C++ header.
- Numerical cross-check: >1000 random deformation gradients against
  centered finite differences in Python. Full Godot native build and
  CI test results should be checked before deployment.
