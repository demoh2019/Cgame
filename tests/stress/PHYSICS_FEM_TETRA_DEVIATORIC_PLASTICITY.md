# Cgame experimental deviatoric (J2-like) FEM plasticity

This extension adds **objective, isochoric, tensorial plastic
rest-shape deformation** for the existing cooked, convex, tetrahedral
GodotPhysics3D SoftBody FEM simulation meshes.

It complements the existing scalar *volume* plastic creep, per-tetra
damage, plastic reinforcement fibers, three hyperelastic material
models (Neo-Hookean, Mooney–Rivlin and Ogden), and inversion recovery.

## Enable

In Project Settings:

\`physics/3d/solver/soft_body_tetra_fem_compliance = 0.00001\`

\`physics/3d/solver/soft_body_tetra_shear_plastic_rate = 3.0\`

\`physics/3d/solver/soft_body_tetra_shear_plastic_yield = 0.2\`

\`physics/3d/solver/soft_body_tetra_shear_plastic_max_strain = 2.0\`

Defaults are **rate=0** (feature OFF), yield=0.2, max cumulative
equivalent plastic strain=2.0. The extra Jacobi eigenanalysis per tetra
is completely skipped at rate=0.

## Physical approximation

For current deformation gradient F=Ds*invDm, form objective
right Cauchy–Green metric C=FᵀF. A 3×3 symmetric Jacobi eigen-solve
gives principal stretches σᵢ and material eigenvectors Q.

Principal Hencky strains lᵢ=ln σᵢ.
Deviatoric strain eᵢ=lᵢ−mean(l); Σeᵢ=0.
A strain-space J2-like equivalent yield measure is

\`e_eq = sqrt(2/3 * sum(e_i^2))\`.

When e_eq > yield, set

\`f = 1−exp(−rate*dt)\`

\`d_equivalent = min(f*(e_eq−yield), max_accumulated−accumulated)\`

\`d_i = e_i * d_equivalent/e_eq\`

and update only the rest inverse matrix:

\`invDm_new = invDm * Q*diag(exp(-d_i))*transpose(Q)\`.

This relaxes elastic shear while retaining volume because Σd_i=0 and
det(Q*diag(exp(-d))*Qᵀ)=1. The tetra's rest.volume and
rest.signed_det, lumped masses, original gas volume and global shell
volume target remain **unchanged**. Plasticity is **irreversible**:
the rest matrix persists until mesh rebuild.

It is a finite-strain deviatoric **strain-space radial return**, not
a calibrated stress-based von Mises return-mapping constitutive
law. There is no isotropic/kinematic hardening, fracture topology,
grain modeling or mesh tearing.

## Stability

- 32 Jacobi sweeps maximum per enabled tetra; eigenvalues limited
  to finite, nonsingular 1e-12..1e12.
- Checks positive FEM orientation, finite inverse-rest matrices and
  a determinant-one correction; invalid geometry never mutates state.
- Cumulative equivalent plastic strain capped, max 4.0 configurable.
- One extra double scalar per cached tetra, no solver-time buffers.
- Update occurs once per physics tick on predicted positions, before
  XPBD positional projections, and works with all three elastic FEM
  models. Pinned vertices and their velocities remain untouched.
- No implicit guarantee of accuracy for very ill-conditioned FEM
  elements; errors are rejected rather than allowed to spread.

## Tests

C++ doctest:
\`tests/servers/test_physics_fem_tetra_deviatoric_plasticity.cpp\`

float/double compiler/runtime smoke test:
\`tests/stress/test_physics_fem_tetra_deviatoric_plasticity_compiler.cpp\`

Numerical and source checks:
\`python3 -m unittest discover -s tests/stress -p 'test_physics_fem_tetra_deviatoric_plasticity.py' -v\`

**Future work:** stress-based Drucker–Prager/von Mises flow rules,
hardening, cohesive fracture, and generic tetrahedral meshes with
interior nodes. A real fracture solver will require dynamic topology
and collision-mesh management, not merely reduced stiffness.
