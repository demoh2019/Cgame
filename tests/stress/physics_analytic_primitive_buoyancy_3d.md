# GodotPhysics 3D: analytic water displacement for spheres and upright capsules

## Context and external engine reference

Jolt Physics' `Body::GetSubmergedVolume()` and
`Body::ApplyBuoyancyImpulse()` use the submerged volume and center of
buoyancy to apply lift and drag. Cgame already has a horizontal fluid
plane, but it approximated **every** shape's submerged fraction as the
height of its world AABB under that plane divided by its full AABB
height. This overstates immersion of round shapes near their bottom
and misplaces the resulting hydrostatic torque on compound bodies.

This change computes **analytic exact displaced-volume fractions and
centers of buoyancy for supported round primitives**. The existing
bounded AABB approximation remains as a fallback. No Jolt source code
has been copied.

## Sphere: exact spherical cap

For a world-space sphere of radius `r`, center `c`, and a horizontal
water surface, let `h = clamp(surface_y - (c_y-r), 0, 2r)` and `t = h/r`.

- `V_submerged / V_total = t²(3-t)/4`.
- `center_buoyancy.y = c_y - 3r(2-t)² / [4(3-t)]`.
- `center_buoyancy.xz = c.xz`.

For example, for `r=1, h=0.5`, a sphere has **15.625%** of its volume
submerged, **not 25%** as the AABB height rule predicts. The exact
buoyancy center is `c_y - 0.675`.

The formula is valid for rotated spheres with *uniform* scale or a
uniform reflection. Sheared and nonuniformly scaled spheres are
ellipsoids and retain the original AABB approximation.

## Capsule: exact vertical hemisphere–cylinder integration

For an upright capsule of radius `r` and overall height `H`,
the cylindrical length is `L = H - 2r`. Integrate the circular
horizontal sections from the bottom to the surface in three regimes:

1. Lower spherical cap: `0 <= h <= r`.
2. Uniform-area cylinder: `r < h <= r + L`.
3. Upper spherical cap: `r + L < h <= 2r + L`.

The implementation evaluates dimensionless volume and first-moment
polynomials; the buoyancy center is the first moment divided by the
submerged volume. The result continuously matches at both transition
planes, and a zero-length cylinder reduces to the sphere formula.

For `r=1, H=4` with `h=0.5`, the submerged-volume fraction is
**6.25%**, not the AABB's **12.5%**, and the buoyancy center is at
`center_y - 1.675`. The center is `center_y - 0.85` for half
submersion.

The exact capsule path requires a uniformly scaled, upright capsule.
Tilted or sheared capsules and nonuniform transforms fall back to the
previous water model.

## Integration, performance and compatibility

The existing per-shape fluid loop in
`modules/godot_physics_3d/godot_body_3d.cpp` checks whether the shape
is a sphere or capsule and whether the composed shape transform is a
uniform similarity transform; it also verifies upright orientation
for capsules. The computed analytic `GodotPhysicsFluidSample3D` then
flows into Cgame's existing *buoyancy force, center-of-buoyancy torque,
quadratic drag and angular damping* code unchanged.

The model remains off when
`physics/3d/fluid_plane/enabled = false` (the default), and legacy
uniform buoyancy remains unchanged when the advanced plane is off.
No per-body allocations, caches or public scripting API changes.
An eligible immersed sphere/capsule uses a few extra arithmetic
operations but no numerical integration loops.

The formulas are exact for the supported primitive geometry in a
horizontal water plane, up to floating-point precision. The full
physics model still approximates viscous drag and flow and does not
simulate liquid surfaces, sloshing, air bubbles, wave forces,
hydrodynamic lift, or exact concave geometry.

## Validation

Native C++:
`tests/servers/test_physics_fluid_analytic_primitives_3d.cpp`
checks dry/quarter/half/full spherical caps, three capsule integration
regimes, displaced-volume centroids, degenerate capsule-to-sphere
equivalence, uniform scale, mirror transforms, tilted capsule
rejection and nonuniform scale fallback.

Independent Python:
`tests/stress/test_physics_fluid_analytic_primitives_3d.py`
numerically integrates **606 capsule cases** with midpoint
quadrature over up to 1500 axial cross-sections each and checks
source wiring. A separate Python cross-check has compared 300 random
capsule configurations using 3000 cross-sections per case, with
maximum volume fraction error less than `2e-7` and center error less
than `1e-6` in project units in that sample. **These are reference
checks, not compiled C++ results.**

Engine headless:
`tests/stress/physics_exact_primitive_buoyancy_3d_regression.gd`
creates a radius-one sphere and an upright radius-one, height-four
capsule, submerged `h=0.5` at density 1 with mass 1. Both have
exact displaced volume `5*pi/24` and initially sink; the prior
AABB method overestimates both volumes enough to incorrectly make
them rise. A dry sphere falls faster, providing a gravity control.

```bash
python3 -m unittest discover -s tests/stress \
  -p 'test_physics_fluid_analytic_primitives_3d.py' -v

./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path tests/stress \
  --script res://physics_exact_primitive_buoyancy_3d_regression.gd
```

Compile Cgame with `tests=yes` and run the native `[Physics]`
cases. Run the existing `physics_submerged_fluid_plane_3d_regression.gd`
as well to cover off-center compound buoyancy and current.

The remote build host has been offline, so native compilation and
headless Godot execution have **not** been verified in this session.
Measure CPU, RSS and simulation correctness before claiming any
production-speed improvement.
