# Principal-stretch bounds for volumetric FEM soft bodies

This adds optional **minimum and maximum singular-value limits** on the
deformation gradient of each tetrahedron in Cgame's built-in GodotPhysics3D
SoftBody3D solver. Unlike existing XPBD edge-length limits on a shell,
these limits operate on the full **3D deformation gradient** of each
tetrahedral element and therefore constrain both local extension and
compression even for shearing deformations.

## Project Settings

```ini
physics/3d/solver/soft_body_tetra_fem_compliance = 0.00001
physics/3d/solver/soft_body_tetra_principal_min_stretch = 0.65
physics/3d/solver/soft_body_tetra_principal_max_stretch = 1.40
physics/3d/solver/soft_body_tetra_principal_limit_compliance = 0.000001
```

- **Min stretch**: `0` (default) disables minimum limiting. Valid range
  when enabled: `0 < min <= 1`. The lower bound prevents extreme local
  collapse along a principal deformation direction.
- **Max stretch**: `0` (default) disables maximum limiting. Enabled values
  are clamped to `1..16`. The upper bound prevents extreme extension.
- **Limit compliance**: `0` (default) means a hard XPBD local cap;
  positive values soften the limiter. This is independent from the
  main FEM material compliance and is divided by `dt²` before solving.

Both limits are disabled by default. The native feature only runs when
**volumetric FEM is already enabled** via a positive
`soft_body_tetra_fem_compliance`. It accepts either automatically cooked
convex tetrahedra or explicit imported tetra connectivity. No new mesh,
particle or body is created.

## Algorithm

For each tetra:
`F = Ds * inverse(Dm)`, `C=F^T F`, and sorted principal stretches are
`sigma = sqrt(eig(C))`. A deterministic symmetric 3×3 cyclic Jacobi
solver finds the eigenvalues and right material eigenvectors in double
precision. At each nonlinear XPBD iteration, unilateral constraints are:

```text
C_upper = sigma_max - max_bound
C_lower = min_bound - sigma_min

d(sigma)/dF = (F*u / sigma) outer u

dC/dx_b,c,d = (+/-) (F*u / sigma) * (u dot invDm_row)
dC/dx_a = -sum(dC/dx_b,c,d)

new_lambda = min(0, lambda - (C+alpha*lambda)/(sum(inv_mass*|grad|²)+alpha))
delta_x = inv_mass * (new_lambda-lambda) * grad
```

A constraint with no positive violation releases its old multiplier.
New projective steps are backtracked up to 12 times and rejected if
they invert the tetrahedron or increase its existing violation.
Pinned nodes have zero inverse mass and do not move.

This is a local nonlinear strain-limiting safety mechanism, **not**
permanent plasticity, remeshing, crack formation or a replacement
for nonlinear elastic material forces. Under large multi-axis
distortions, multiple XPBD iterations may be needed for convergence.

## Compatibility and verification

- All 3 elastic material models (Neo-Hookean, Mooney–Rivlin, Ogden) remain
  independent of this optional limiter.
- FEM material damage and fiber plasticity still work as configured.
- The existing inversion-recovery pass, if enabled, precedes the
  hyperelastic stress and principal caps.
- Zero limits allocate no principal-lambda scratch or runtime loops.
- `tests/servers/test_physics_fem_tetra_principal_limits.cpp`:
  15 native C++ tests for rotations, shear, gradient consistency, mass/pins,
  inversion, rest orientation, timestep multipliers and compliance.
- `tests/stress/test_physics_fem_tetra_principal_limits_compiler.cpp`:
  a standalone native compile/runtime smoke of the production C++ header,
  under float32 and float64.
- `.github/workflows/physics-fem-principal-limits.yml`: CI contract.

A separate NumPy reference validation checked 1500 random positive-J
deformations: maximum stretch error ~1.1e-15 against SVD and maximum
analytical gradient error ~5.7e-10 versus centered finite differences.
These checks do **not** replace full native C++ integration tests.

## Background

- PhysX deformable volume uses tetrahedral FEM simulation meshes:
  https://nvidia-omniverse.github.io/PhysX/physx/5.8.0/docs/DeformableVolume.html
- XPBD mathematics:
  https://developer.blender.org/docs/features/nodes/xpbd_solver/xpbd_method/
