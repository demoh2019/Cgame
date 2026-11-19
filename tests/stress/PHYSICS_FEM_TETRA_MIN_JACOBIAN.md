# Experimental XPBD tetrahedral minimum-Jacobian anti-collapse

## What it solves

Cgame already has an experimental convex closed-shell tetrahedralization
and volumetric compressible Neo-Hookean FEM with material fibers and
objective viscosity. That FEM correctly evaluates

    W(F) = mu/2 * (trace(F^T F)-3) - mu*log(J) + lambda/2 * log(J)^2

only for **positive** deformation determinant \`J=det(F)\` and rejects
an inverted / singular element. It does not, by itself, project an
**already inverted** tetrahedron to a valid configuration.

The new **one-sided XPBD minimum-Jacobian** constraint is a small,
allocation-free correction which remains defined at \`J <= 0\`.
It can restore local orientation from a flattened or inverted
tetrahedron and prevent further compression under suitably converged
iterations, without requiring log(J) to be valid.

The method is related to XPBD tetra-volume constraints in Jan
Bender's PositionBasedDynamics and FEM inversion-handling strategies
used by deformable engines such as PhysX. Cgame's implementation is
independent; no external source is copied.

## Configuration — GodotPhysics3D

Configure in ProjectSettings **before creating the physics space**:

    physics/3d/solver/soft_body_tetra_min_jacobian = 0.20
    physics/3d/solver/soft_body_tetra_min_jacobian_compliance = 0.0

- \`soft_body_tetra_min_jacobian\` is dimensionless, **0 disables** the
  feature completely and preserves legacy behavior, with **0 additional
  per-tetra allocations** or work. Valid range is [0,1].
- \`0.2\` means a minimum target signed volume ratio of 20% of the
  original tetrahedron volume. \`1\` disallows compression in the
  ideal converged unilateral solver, but still permits expansion.
- \`soft_body_tetra_min_jacobian_compliance\` has default **0**
  (hard XPBD inequality). Increase above zero for a softer protective
  threshold that can be violated under load.
- No positive Neo-Hookean FEM compliance is required. The guard can
  run independently of elastic FEM, but it needs an eligible
  consistently wound **closed strictly convex** soft-body mesh
  to cook tetrahedra.
- Current convex fan cooker supports at most **2048 nodes / 4096
  triangle faces**. Nonconvex or nonmanifold inputs are rejected.

Typical optional combination:

    physics/3d/solver/soft_body_tetra_fem_compliance = 0.00001
    physics/3d/solver/soft_body_tetra_fem_poisson_ratio = 0.3
    physics/3d/solver/soft_body_tetra_min_jacobian = 0.2
    physics/3d/solver/soft_body_tetra_min_jacobian_compliance = 0.0

## Mathematics

At any tetrahedron, with rest edge matrix Dm and current edge
matrix Ds:

    J = det(Ds) / det(Dm)
    C = J - J_min >= 0
    lambda >= 0

An orientation-invariant ratio is used: it works with **negative or
positive rest winding**.

Gradients are computed from the scalar triple product:

    gb = cross(c-a, d-a)/det(Dm)
    gc = cross(d-a, b-a)/det(Dm)
    gd = cross(b-a, c-a)/det(Dm)
    ga = -gb-gc-gd

The mass-weighted XPBD correction:

    alpha = compliance / dt^2
    w = sum_i(inv_mass_i * dot(g_i,g_i))
    delta_lambda = -(C + alpha*lambda) / (w + alpha)
    next_lambda = max(0, lambda+delta_lambda)
    delta_x_i = inv_mass_i * g_i*(next_lambda-lambda)

The nonnegative multiplier prevents the constraint from pulling
uncompressed/rest tetrahedra toward the minimum — **expansion is
unconstrained**. The gradient exists even at J=0 or J<0, so a flat
tetrahedron with at least one nonzero gradient and movable vertex
can move into a positive orientation.

When the candidate overflows, or when a positive inequality impulse
would *decrease* the Jacobian, a bounded 12-attempt backtracking pass
shortens the step. All computed positions and the multiplier are
committed **atomically** only if valid and accepted.

The per-tetra multiplier is reset at the start of each physics step,
then reused across XPBD solver iterations. The guard is applied
**after other material/tether projections** in each iteration, so
FEM may be able to resume once inverted elements have been repaired.
The guard does not modify rest geometry, material parameters or mesh
topology; all pinned particles remain pinned.

## Performance

The default 0 threshold:
- No tetra cooking solely for this feature.
- No per-tetra extra multiplier buffer.
- No additional solver iteration work.

When enabled:
- **O(tetrahedra)** work per XPBD iteration.
- One \`LocalVector<double>\` multiplier per tetra: **8 bytes per tet**.
- No heap allocations within the hot Jacobian projection.
- Cross products and Jacobian calculations use double intermediates,
  improving large/small scale stability.

## Caveats

- This is a protective unilateral volume-ratio XPBD constraint, **not**
  an exact guaranteed hard non-inversion theorem. Finite iterations,
  sharing vertices, contacts processed later in the step, external
  impulses and severe deformation can still temporarily produce
  inverted or subthreshold tetrahedra.
- Fully coincident positions have zero volume gradient and cannot be
  repaired without an externally chosen separation direction.
- Only the **existing closed-convex fan tetrahedralization** is used,
  not a general 3D tetrahedral mesher for concave or arbitrary solids.
- Rest material can be affected by other cloth/solid constraints.
  When volume plasticity is enabled, this guard always measures
  relative to the original FEM tetra rest shape, not a softened
  plastic volume target.
- Enabling a large hard minimum J and high FEM stiffness together
  may make multi-constraint convergence difficult; tune iterations,
  compliance, frame delta and substeps.
- It does not perform fracture, cutting, tearing, true fluid coupling,
  self-contact generation or collision topology repair.

## Testing

Independent numerical/source tests:

    python3 -m unittest discover -s tests/stress \
      -p test_physics_fem_tetra_min_jacobian.py -v

Native test suite:

    scons platform=linuxbsd target=editor dev_build=yes tests=yes -j4
    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
      --test-case="[PhysicsFEMMinJ]*"

Native tests cover Jacobian sign, flat and inverted recovery, actual
FEM resumption, pinning, unilateral inactive/rest behavior, hard vs
compliant response, stored multiplier release, negative original
winding, translation, rotation, tiny tetrahedra, singular gradients
and invalid/nonfinite input atomicity.

### Merge gate

Run a deformation scene with a closed convex cube/soft solid hit by
a large impulse, measure the minimum FEM J for all tetrahedra every
physics tick before and after correction, and verify no NaNs.
Compare disabled vs enabled at 60 Hz and 120 Hz, and use stress
scenes with 100/1k/4k tetrahedra to compare p50/p95 CPU and peak
memory. Evaluate interactions with Neo-Hookean FEM, directional
fibers, strain limits, volume plasticity and soft-soft collisions.
Only merge after native build/test and scene validation.

## Background

- PositionBasedDynamics XPBD tetra volume and FEM tetra:
  https://positionbaseddynamics.readthedocs.io/en/latest/api/class_p_b_d_1_1_x_p_b_d.html
- NVIDIA PhysX deformable overview:
  https://nvidia-omniverse.github.io/PhysX/physx/5.7.0/docs/DeformableBodyOverview.html
