# Coupling tetrahedral FEM damage to reinforcing material fibers

Cgame's built-in Godot Physics 3D backend has independent opt-in
**Neo-Hookean FEM elasticity**, **tension-only anisotropic fiber
reinforcement**, and **irreversible FEM element damage**. Previously,
progressive damage softened the isotropic tetrahedral FEM energy but
the fiber row remained completely intact. A heavily damaged element
could therefore become soft in one mode yet retain its original fiber
stiffness. This change unifies the material response.

## Algorithm

The existing single per-element `xpbd_fem_damage` scalar is shared by
both constraints. If tetra damage history exists, each fiber XPBD row
uses the same bounded compliance increase as Neo-Hookean FEM:

```
fiber_alpha_effective = fiber_alpha/(1-damage)
0 <= damage <= 0.95
```

The accumulated damage is read-only during XPBD iterations; the existing
frame-level evolution still runs once on pre-projection strain. No extra
persistent per-fiber or per-tetra buffers, collision passes, or updates
are introduced. If damage is disabled (rate=0), or no damage history is
cooked, the fiber solver uses its exact previous compliance.

Damaged materials soften but their tetrahedron/rest matrix and surface
triangles do not split, and material fibers are not removed: **this is
NOT fracture, crack propagation, or fiber severing**.

## Configuration

Enable existing settings under `physics/3d/solver`:
- `soft_body_tetra_fem_compliance > 0` for tetrahedral FEM.
- `soft_body_tetra_fiber_compliance > 0` for directional reinforcement.
- `soft_body_tetra_damage_rate > 0` for progressive material damage.
- `soft_body_tetra_damage_yield_strain` sets onset of damage.

The existing convex, closed-surface tetrahedron cooker remains required.
No new ProjectSetting is introduced by this change.

## Verification

- `tests/servers/test_physics_fem_tetra_fiber_damage.cpp` includes
  6 native C++ checks for weaker fibers at greater damage, finite caps,
  exact pinning, rigid material rotation and progressive history.
- `tests/stress/test_physics_fem_tetra_fiber_damage.py` includes
  4,000 seeded independent XPBD checks and source/config contracts.
- `.github/workflows/physics-fem-fiber-damage.yml` runs the Python
  reference tests on the PR.

As with existing experimental FEM, native Godot C++ compilation,
scene-level correctness and CPU/RSS benchmarking are still required
before production use.
