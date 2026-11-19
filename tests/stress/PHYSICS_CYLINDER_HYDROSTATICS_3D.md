# Exact/robust rigid CylinderShape3D buoyancy in GodotPhysics3D

## Gap and reference

Cgame already has an optional horizontal fluid plane, and shape-aware
displacement for spheres, upright capsules, oriented boxes and convex
hulls. A **CylinderShape3D** still uses the submerged *height of its world
AABB*, which cannot capture the circular cross-section, the true
submerged volume near its curved side, or the lateral first moment of a
tilted cylinder.

Jolt's `Shape::GetSubmergedVolume` and `Body::ApplyBuoyancyImpulse`
operate on the same physically meaningful quantities: the total
volume, submerged volume and submerged center of buoyancy. This Cgame
implementation uses its own circle-segment mathematics and has not
copied Jolt source code.

## Mathematical model

A uniformly scaled right circular cylinder of radius `r`, total
height `H`, center `c`, and normalized axis `a` lies at axial
coordinate `s ∈ [-H/2, H/2]`.

Let `alpha = a_y`, `beta = sqrt(1-alpha²)` and
`e=(Y-alpha*a)/beta`; `e` is the upward direction within each
cross-sectional disk. The local water level at axial coordinate `s`
is

```text
u(s) = (surface_y - c_y - alpha*s) / beta
t(s) = clamp(u(s)/r, -1, 1)
```

The circular disk area and perpendicular first moment below the waterline
for a partially submerged disk are

```text
A(t) = r² [acos(-t) + t*sqrt(1-t²)]
M_perp(t) = -(2/3) r³ (1-t²)^(3/2)
```

The cylinder's submerged **volume**, axial first moment and transverse
first moment are integrals of `A`, `s*A` and `M_perp` over `s`.
Their first-moment ratios produce the *actual 3D center of buoyancy*:

```text
V_wet = integral(A ds)
center_buoyancy = c + a * integral(s*A ds)/V_wet
                    + e * integral(M_perp ds)/V_wet
V_total = pi*r²*H
```

These quantities are then handed to Cgame's existing
`lift = -gravity * fluid_density * V_wet` and
`torque = (center_buoyancy - center_mass) × lift`.

### Solver and numerical stability

- Dry/full cylinder: exact early exit from its **true** vertical
  support extent, not AABB.
- Exactly vertical axis: analytic cut of the cylinder's axial interval.
- Exactly horizontal axis: constant circular-segment area and moment,
  analytically integrated over the cylinder length.
- General tilt: closed-form antiderivatives for
  `A(t)`, `t*A(t)` and `M_perp(t)`, splitting at the dry/full disk
  transition coordinates. This is O(1) per body, with at most three
  subintervals.
- Almost horizontal, moderate tilt extent: a **fixed symmetric
  16-point Gauss-Legendre rule** avoids catastrophic cancellation
  between nearly equal antiderivatives in the first moment.
- Almost horizontal, infinitesimal total tilt extent: an analytic
  first-order central expansion retains the axial lever even for
  extremely long cylinders (unlike treating them as precisely
  horizontal). Its omitted volume term is ≤ O(10^-12) in the normalized
  regime where the branch runs.
- All intermediate geometry uses double precision, fixed stack
  variables, no heap allocation, and finite checks. Invalid results
  fall back to the previous AABB approximation.

The stable quadrature/expansion branches mean the full solver is
**numerically accurate rather than an everywhere-symbolic exact closed
form**. The circle-section formulas themselves are exact.

## Integration and compatibility

In `modules/godot_physics_3d/godot_body_3d.cpp`, a
`SHAPE_CYLINDER` under a **similarity** transform now uses
`godot_physics_fluid_cylinder_sample_3d`. The code adjusts the
total shape volume used in angular fluid damping using its computed
world-space cylinder volume, just like the oriented-box/convex-hull
paths.

The original AABB approximation remains for sheared or nonuniformly
scaled cylinders, which have **elliptical** cross sections and require
a separate affine cylinder integrator. No public API or project setting
is introduced. The entire fluid-plane model remains disabled when
`physics/3d/fluid_plane/enabled=false` (default).

This is **rigid-body hydrostatics**, not a dynamic SPH/PBF liquid or
a moving free-surface simulation. Current drag area estimates are still
approximations; hydrodynamic wake, vortices, splash and wave effects
are not added.

## Regressions and performance

C++ tests (`tests=yes`) cover vertical and horizontal analytic
limits, arbitrary tilt and torque, axis inversion, complementary
waterlines, full/dry, long cylinders, tiny near-horizontal slopes and
invalid inputs:

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="*[PhysicsCylinderFluid]*" --success=true --no-colors
```

Independent Python source and mathematical tests use direct
**composite Simpson quadrature** of circular cross-sectional area,
axial and transverse moments, including 1200 randomized tilted
configurations, antiderivative identities, axis inversion and small-angle
stability:

```bash
python3 -m unittest discover -s tests/stress \
  -p test_physics_fluid_cylinder_3d.py -v
```

Native engine runtime:

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path tests/stress \
  --script res://physics_cylinder_buoyancy_3d_regression.gd
```

The scene uses radius-1, height-4 cylinders. A horizontal cylinder with
bottom at y=-0.5 displaces exactly
`4*[acos(0.5)-0.5*sqrt(0.75)] ≈ 2.45674 m³` of water; the old
AABB fraction incorrectly predicts `π ≈ 3.14159 m³`. At mass 2.8
and water density 1, the **real cylinder sinks**, whereas AABB says
it should float. The test compares upright and fully dry bodies and
checks opposite restoring torque for ±45° tilted cylinders.

For CPU and RSS profiling, two registered stress cases create 64–2048
rotated cylinders with identical transform, velocity and mass, but
fluid plane off/on. The cases report physics timing and resource usage
through `tests/stress/run.py`:

```bash
python3 tests/stress/run.py \
  --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --preset smoke --render-mode headless \
  --case physics_cylinder_fluid_3d_disabled,physics_cylinder_fluid_3d_enabled \
  --output physics-cylinder-fluid-stress.json
```

These comparisons measure the **overall additional fluid-plane cost**,
not a baseline against the prior AABB-only shape path. To compare the
algorithms, run the same test against the parent `develop` revision
on the same hardware.

Native compilation, GDScript execution, regression scene success and
platform profiling have not yet been proven. Do not merge to
`develop` until all relevant CI passes. Reconcile nearby
`godot_body_3d.cpp` changes from the still-draft capsule and
ellipsoid PRs (#636 and #652) before landing multiple fluid features.
