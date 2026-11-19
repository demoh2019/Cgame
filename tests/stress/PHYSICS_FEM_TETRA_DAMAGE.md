# Irreversible scalar damage in SoftBody3D tetrahedral FEM

The built-in Godot Physics 3D solver now has an opt-in **local scalar
continuum-damage approximation** for closed convex soft bodies with cooked
tetrahedra. Unlike ordinary elastic recovery, each volume element retains
its own damage history until the rest mesh/space is rebuilt.

## Settings

```ini
physics/3d/solver/soft_body_tetra_fem_compliance = 0.00001
physics/3d/solver/soft_body_tetra_fem_poisson_ratio = 0.3
physics/3d/solver/soft_body_tetra_damage_yield_strain = 0.25
physics/3d/solver/soft_body_tetra_damage_rate = 3.0
```

`soft_body_tetra_damage_rate = 0` (default) performs **no extra damage
calculation or per-tetra damage allocation**. A positive rate is meaningful
only when the elastic FEM compliance is also positive. The yield strain is a
dimensionless equivalent strain derived from the normalized, undamaged
Neo-Hookean material energy; the rate is a phenomenological growth
coefficient, not a calibrated fracture toughness.

## Algorithm

For each tetrahedron with rest volume `V0`, compute its normalized
Neo-Hookean energy `W` with unit Young's modulus, then

```text
strain_eq = sqrt(2*W/V0)
excess    = max(0, strain_eq - yield)
d_next    = d + (0.95-d)*(1-exp(-rate*excess*delta))
alpha_eff = (compliance/delta²)/(1-d_next)
```

Damage `d` is irreversible in `[0, 0.95]`, so each tetra retains at least
5% of its original stiffness. `alpha_eff` is computed per element and
reused across iterations in that physics step. We update damage **once per
physics tick on predicted positions**, before XPBD projects away the peak
strain. Fully inverted elements are not damaged or projected by this mode.

## Limits

This is **stiffness degradation**, NOT cutting, tearing, detaching vertices,
creating new collision topology, changing material mass, or a general
mesh-cooking pipeline. Shared vertices remain shared. Other optional
constraints (surface links, shape matching, fiber reinforcement, shell
volume preservation) can still resist movement, even when FEM damage is high.
If used simultaneously, tune them carefully.

The implementation follows standard scalar continuum-damage ideas, but is
not copied from PhysX or SOFA. The underlying tetra solver remains the
project's existing Neo-Hookean XPBD system.

## Validation

- `tests/servers/test_physics_fem_tetra_damage.cpp`: 12 native C++ tests.
- `tests/stress/test_physics_fem_tetra_damage_compiler.cpp`: standalone
  production-header compiler/runtime smoke, float and double.
- `.github/workflows/physics-fem-tetra-damage.yml`: runs the smoke test
  for changes to the damage system.
- Native full-engine build and integration tests remain separately required.
