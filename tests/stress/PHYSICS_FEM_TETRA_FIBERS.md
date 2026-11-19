# Tetrahedral FEM — directional fiber reinforcement

Experimental **tension-only anisotropic reinforcement** for the built-in
Godot Physics 3D SoftBody3D convex-body Neo-Hookean tetrahedral FEM.

This adds a simple class of *transversely anisotropic* material responses:
fibers carry tensile load along a user-selected undeformed material
direction and do not act like stiff bars in compression. It is useful as
a first approximation for tendons, tissue fibers, soft composites and
reinforced rubbers.

## Enable

In Project Settings under `physics/3d/solver`:

- `soft_body_tetra_fem_compliance > 0` — existing FEM must be active.
  Currently requires a closed, consistently oriented **convex** surface
  that can be cooked into a fan of tetrahedra.
- `soft_body_tetra_fiber_compliance > 0` — new optional fiber XPBD
  compliance; default **0** disables all fiber work and multiplier
  allocations. Smaller positive values mean stiffer fibers.
- `soft_body_tetra_fiber_axis` — material direction in undeformed FEM
  rest coordinates (default `Vector3(1, 0, 0)`), automatically
  normalized, rejected if zero/nonfinite.

No changes to existing Jolt physics paths.

## Physical model

The rest material fiber direction `a0` is mapped to the current
configuration by the deformation gradient `F=Ds*Dm^-1`. The stretch
is `s=|F*a0|`. Solve the unilateral XPBD constraint

```
C = sqrt(rest_tet_volume) * (1 - s) >= 0
lambda >= 0
alpha = fiber_compliance / dt^2
```

Stretched fibers (`s>1`) gain a nonnegative tension multiplier. The
four nodal gradients follow the tetrahedral shape-function derivatives,
and sum to zero. Rigid translation and rotation therefore do not
create false strains; mass-weighted projections conserve total linear
and angular momentum for free vertices. Pins with zero inverse mass
remain fixed. Under compression the constraint remains slack.

One XPBD lambda per tetrahedron is allocated **only when fiber
compliance is positive**. Multipliers are reset once per physics step,
then retained across nonlinear solver iterations. Proposed positions
are checked transactionally for finiteness and positive relative
tetra volume; up to 12 backtracking trials prevent an active fiber
from inverting a previously valid element.

This is a **simple one-family tension-only fiber model**, not a full
anisotropic hyperelastic energy (e.g. Holzapfel–Gasser–Ogden), fiber
dispersion, active muscles, rupture or orthotropic FEM.

## Validation and limitations

- `tests/servers/test_physics_fem_tetra_fiber.cpp`: 7 C++ tests for
  axial extension, slack compression, transverse stretch, rigid rotation,
  unequal inverse masses, pins, compliance, inversion, invalid inputs.
- `tests/stress/test_physics_fem_tetra_fiber.py`: 5,000 random
  mathematical reference cases and source wiring.
- `.github/workflows/physics-fem-tetra-fiber.yml`: focused Python CI.

Full engine-level C++ builds and native deforming-mesh scenes remain
necessary before relying on this experimental mode. Compare results
under differing time steps, tetra resolution and pin configurations.
The fiber setting does not tetrahedralize concave shells or import
arbitrary FEM meshes by itself.
