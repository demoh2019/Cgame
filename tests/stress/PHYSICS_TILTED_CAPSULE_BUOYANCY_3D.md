# GodotPhysics3D: tilted capsule buoyancy and hydrostatic torque

## Why this is needed

Cgame already has a fluid-plane buoyancy model with exact spherical caps,
vertical capsule immersion, rotated box clipping and convex-hull clipping.
**Tilted** capsules currently fall back to the height fraction of their
world AABB. This can overstate/understate the displaced fluid volume and
places the lift at the wrong point, missing the restoring torque on
partially submerged rods, buoyant capsules and cylindrical floats.

The approach builds on rigid-body buoyancy using displaced liquid volume
and the *centroid of that submerged volume* (Archimedes' principle),
as in Jolt's `Body::GetSubmergedVolume` / `ApplyBuoyancyImpulse`
workflow. The mathematical implementation is original to Cgame; no
external solver or code has been copied.

## Method

A uniformly scaled capsule is a cylinder of length `L = H - 2r`
between two hemispheres of radius `r`.

Take the capsule's world-space axial unit vector `a`, with vertical
component `a_y`, and the vertical unit vector `Y`.
For each axial position `s` the perpendicular disk has radius

- `R(s) = r` in the cylindrical section;
- `R(s) = sqrt(r² - (|s|-L/2)²)` in the hemispherical ends.

The world vertical coordinate within the disk is
`center_y + a_y*s + beta*u`, where
`beta = sqrt(1-a_y²)`, and `u` is measured along the unit vector
`(Y - a_y*a)/beta`.

The disk below the horizontal waterline `Y = height` is a circular
segment. Let `h = (height-center_y-a_y*s)/beta`; for `-R < h < R`:

- Submerged disk area: `A = R²[acos(-h/R) + (h/R)*sqrt(1-(h/R)²)]`.
- First transverse moment: `M = -2/3 * (R²-h²)^(3/2)`.

Integrate over the axial coordinate to obtain **submerged volume,
axial first moment and transverse first moment**. The world buoyancy
center is the capsule center plus the corresponding axial and
transverse vector offsets.

### Numerical and fast paths

- Exactly dry/full: compare waterline with the capsule's true vertical
  support interval; return without any quadrature.
- Zero cylinder length: use the existing analytical sphere solution.
- Nearly upright: reuse the existing exact vertical capsule solution.
- Otherwise: 8-point Gauss-Legendre with 16 bounded panels per piece.
  Integrate the two hemispherical ends separately.
- Split long cylinders at their exact dry/full circular-disk transition
  positions, and integrate fully wet ranges analytically. This avoids
  skipping narrow wet bands on extreme length/radius ratios.
- Exactly horizontal cylinder: integrate the constant submerged
  circular segment analytically over its length.

The integration has fixed working memory (arrays on the stack), no
per-contact allocations, no global caches and no additional path when
the fluid plane is disabled.

This is **bounded numerical quadrature**, not an exact closed-form
tilted-capsule solution; the error depends on geometry and waterline.
The fast and dry/full paths are exact for the supported primitive up
to floating-point precision.

## Compatibility

The existing `physics/3d/fluid_plane/enabled` flag still defaults to
`false`. No new ProjectSetting or public scripting API is required.

Only valid capsules under rotation plus uniform scaling use the new
integration. Elliptically transformed, sheared or degenerate capsules
retain the existing AABB fallback. The existing force and torque paths
apply `lift = -gravity * fluid_density * submerged_volume` at the
computed center; `lever.cross(lift + drag)` is unchanged. The rest
of the fluid model still uses approximate projected-area drag and does
not simulate free-surface waves, viscosity fields, sloshing or particle
fluid dynamics (SPH/PBF).

## Verification

Native tests:

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="*[PhysicsTiltedCapsule]*" --success=true --no-colors
```

Tests cover horizontally half-wet exact moments, oblique lateral lift
lever, complementary waterlines, axis reversal, full/dry, vertical
and spherical limits, extreme cylinder aspect ratios, and invalid data.

Independent Python reference:

```bash
python3 -m unittest discover -s tests/stress \
  -p 'test_physics_fluid_tilted_capsule_3d.py' -v
```

A deterministic midpoint quadrature separately validates hydrostatic
moments, random mirror symmetry and source wiring.

Actual GodotPhysics3D headless torque regression:

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path tests/stress \
  --script res://physics_tilted_capsule_buoyancy_3d_regression.gd
```

Two half-submerged capsules at opposite 45° tilt must spin in opposite
directions; the fully dry control must not develop fluid torque.

## Benchmark plan and limitations

Compare the previous AABB baseline against the integration on identical
hardware with 32, 128 and 512 floating capsules; sweep orientation
0, 15, 45, 75 and 90 degrees, waterline and long aspect ratios.
Record p50/p95/p99 physics-step time, full-process RSS and buoyancy
volume/centroid error against dense numerical reference.

Do not claim speedup or production-readiness based solely on mathematical
or source tests. The rotated-capsule path is intentionally more expensive
than AABB when partially submerged; compiled-engine and scene validation
are required before any `develop` merge.
