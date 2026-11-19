# Exact affine ellipsoid buoyancy in GodotPhysics3D

## Background and reference

Cgame's optional fluid-plane solver already computes displaced volume and
buoyancy center for spheres, upright capsules, rotated boxes and supported
convex hulls. A sphere with *nonuniform scale or shear*, however, becomes
an ellipsoid; the existing implementation approximates its submerged
fraction by the height of a world-space AABB and its center by the center
of the submerged box. This can introduce significant volume errors near
the waterline and artificial or missing hydrostatic torque.

Jolt's Shape::GetSubmergedVolume / Body::ApplyBuoyancyImpulse interface
returns a submerged volume and center of buoyancy to calculate lift and
torque. This patch follows the same physically grounded *quantity* but
uses an independently derived analytic affine-ellipsoid method; no external
engine code is copied.

## Exact derivation

Let the local sphere radius be `r`, its shape-to-world affine
transform be `x = c + B * u * r` for `|u| <= 1`, with nonsingular
3x3 matrix `B`, and a horizontal water surface `y = h`.
Then the local plane equation is

```text
(B^T Y) · u <= (h - c_y) / r
Y = (0, 1, 0)
H = r * |B^T Y|
t = clamp(1 + (h - c_y)/H, 0, 2)
V_total = (4*pi/3) * r^3 * |det(B)|
V_wet / V_total = t^2 * (3-t) / 4
```

The spherical cap's centroid along its own normalized plane direction
is displaced by the exact amount

```text
delta_y = -3H(2-t)^2 / [4(3-t)]
center_wet = c + ((B B^T) Y / |B^T Y|^2) * delta_y
```

Note the `x` and `z` components of `B B^T Y`: a rotated or sheared
ellipsoid can have **lateral buoyancy-center displacement**, producing
a genuine restoring torque, unlike a centered AABB approximation.

The determinant and first moments use double-precision intermediates,
including world translations. The geometry is exact for affine images
of a sphere, up to ordinary floating-point error.

## Engine integration and backward compatibility

- Implemented in `servers/physics_fluid_ellipsoid_3d.h` with **no heap
  allocation, no buffers, no numerical quadrature**, and no new setting.
- Used inside the existing rigid-body fluid-plane shape traversal in
  `modules/godot_physics_3d/godot_body_3d.cpp`.
- Unchanged original sphere and upright-capsule analytic paths for
  similarity (uniform) transforms.
- Only sphere shapes with nonuniform/skew transforms use the new path.
  Reflected (negative determinant) transforms produce positive displaced
  volume and correctly transformed centroids.
- Existing exact solver's true `V_total` replaces the prior cached
  shape-volume estimate for angular immersion ratio, just like the
  existing oriented-box and convex-hull paths.
- Invalid, singular, near-underflow or non-finite transforms return to
  the previous bounded AABB fallback without adding invalid forces.
- Fluid-plane physics remains **disabled by default**, so normal projects
  see no additional work or changed forces.

### Limitations

This is rigid-body ellipsoid *hydrostatics*, not a particle-fluid solver
or incompressible Navier–Stokes simulation. The horizontal water surface,
quadratic drag area approximation and no overlapping-shape volume
deduplication are unchanged. The engine's general collision subsystem
may still impose limits on nonuniformly scaled physics shapes, which
require native runtime validation.

## Verification

Independent Python quadrature and source contracts:

```bash
python3 -m unittest discover -s tests/stress \
  -p test_physics_fluid_ellipsoid_3d.py -v
```

The reference integrates unit-ball cross-sectional area and first moment
using Simpson's rule, independently of the closed-form cap formulas.
1,000 random sheared/rotated ellipsoids plus 250 reflected and
complementary waterline cases are checked.

Native C++ tests:

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="*[PhysicsEllipsoid]*" --success=true --no-colors
```

Eight tests cover sphere equivalence, ellipsoid exact volume,
rotated torque direction, arbitrary shear, reflection, complementary
wet/dry first moments, large world translations and invalid inputs.

Actual engine runtime test:

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path tests/stress \
  --script res://physics_ellipsoid_buoyancy_3d_regression.gd
```

The scenario compares a radius-1 sphere with a nonuniformly scaled
sphere (`2 × 1 × 0.5`), both at `center_y = 0.5` with the same volume,
same vertical half-height, mass 1 and water density 1. Both should
sink almost identically: exact wet volume is `5*pi/24 ≈ 0.6545`,
while the old AABB height approximation predicts `pi/3 ≈ 1.0472`
and incorrectly makes the ellipsoid float. An entirely dry ellipsoid
provides an independent gravity control.

### Profiling

A ready-to-run scale sweep is registered in `tests/stress/run.py` and
`tests/stress/stress.gd`. It creates 64-2048 independently moving,
rotated, nonuniformly scaled ellipsoids and compares the SAME bodies
with the optional fluid plane disabled and enabled:

```bash
python3 tests/stress/run.py \
  --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case physics_ellipsoid_fluid_3d_disabled,physics_ellipsoid_fluid_3d_enabled \
  --scales 1,2,4,8,16 \
  --frames 120 --repeats 3 --output out/ellipsoid-fluid-scale.json
```

This quantifies the overall cost of fluid-plane forces, **not** a
head-to-head implementation baseline versus old AABB approximation.
For that comparison, benchmark the parent commit on the same hardware
and identical workload. Report median/p95/p99 physics-step times,
process RSS and numerical error across matched runs. The new path is
more arithmetic than the AABB height ratio but has constant O(1)
memory and time and avoids voxel/tetrahedral clipping.

Do not claim production readiness until native CI, the actual
nonuniform-shape headless test and platform benchmarks pass.
