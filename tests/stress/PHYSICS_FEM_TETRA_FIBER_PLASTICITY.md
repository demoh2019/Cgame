# Plastic fiber remodeling for tetrahedral SoftBody3D FEM

**Experimental directional tensile viscoplasticity** for Cgame's built-in
Godot Physics 3D backend. This extends existing Neo-Hookean/Mooney-Rivlin
elastic tetrahedra, objective viscosity, anisotropic tension-only
reinforcement, and damage. It is a simple *fiber-specific permanent
extension law*, not full 3D multiplicative plasticity or fracture.

Inspired by the XPBD approach to compliant, cached material constraints
described in the PositionBasedDynamics solver (without copying code),
and the deformable material models documented for NVIDIA PhysX.

## Settings (Project Settings / Physics / 3D / Solver)

Required existing properties:

- `soft_body_tetra_fem_compliance > 0`: enables FEM tetrahedron cooker.
- `soft_body_tetra_fiber_compliance > 0`: enables directional fiber
  reinforcement and its XPBD multiplier.
- `soft_body_tetra_fiber_axis`: direction in the original material frame.

New optional properties:

- `soft_body_tetra_fiber_plastic_yield_ratio`: defaults to **0.15**.
  A fiber may elongate plastically only beyond its current, evolved
  rest stretch multiplied by `1+yield_ratio`.
- `soft_body_tetra_fiber_plastic_creep_rate`: defaults to **0** (off).
  Positive values, in 1/s, enable the irreversible plastic history.
- `soft_body_tetra_fiber_plastic_max_stretch`: defaults to **3.0**,
  accepted range [1, 16]. Limits growth of permanent fiber extension.

Works only for successfully cooked, closed convex soft meshes; current
Cooker supports no arbitrary non-convex tetrahedral volumes.

## Material law

Let `F=Ds * inverse(Dm)` be the current tetrahedron deformation
gradient, and `a0` the undeformed normalized fiber direction.
Current stretch is `s=|F a0|`. It is invariant to rigid translation
or world rotation.

Each tetra stores one scalar permanent rest stretch `r >= 1`.
If `s > r(1+yield)`, the equilibrium rest stretch is:

```
target = min(max_rest_stretch, s/(1+yield))
fraction = 1 - exp(-creep_rate * dt)
r_next = r + (target-r)*fraction
```

This update occurs exactly **once per physics step**, on predicted
pre-projection positions, not on every XPBD solve iteration. The
result is monotonic (no self-healing), saturates, and has consistent
substep splitting under constant imposed extension.

The tension-only fiber row then becomes

```
C = sqrt(rest_tet_volume) * (plastic_rest_stretch - |F a0|) >= 0
```

and otherwise keeps the same mass weighting, pin semantics, damage
dependent compliance, and inversion-guarded transactional corrections.
Legacy callers pass no rest stretch and retain `1.0` by default.

### Resource and compatibility

A single `real_t` per tetrahedron stores plastic fiber rest stretch,
allocated only if all required settings are enabled. When disabled or
when the mesh is reconstructed, history is released/reset. Zero creep
does not add tensor traversal or persistent RAM to existing scenes.
The rest FEM matrix, mass, isotropic elasticity and collision mesh
remain unchanged. The current plastic law models only permanent fiber
elongation, not volumetric plastic shape, fiber reorientation or rupture.

## Tests

- `tests/servers/test_physics_fem_tetra_fiber_plasticity.cpp`:
  8 native Doctest cases checking material rotation/objectivity, axial vs
  transverse strain, threshold, permanent creep, step subdivision,
  relaxed tension, pins, and invalid/inverted inputs.
- `tests/stress/test_physics_fem_tetra_fiber_plasticity.py`:
  12,000 seeded reference cases (6,000 objective strains, 3,000 step
  subdivisions, 3,000 plastic XPBD projections), plus wiring.
- `.github/workflows/physics-fem-fiber-plasticity.yml`:
  focused reference regression workflow.

Full engine C++ compilation, real scene stress evaluation, comparisons
against mesh refinement and CPU/RAM profiling are still required for
production usage. No third-party source code has been copied.
