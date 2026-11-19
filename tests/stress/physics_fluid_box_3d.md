# GodotPhysics 3D — exact water displacement for oriented BoxShape3D

## Why this matters

Jolt Physics provides `Shape::GetSubmergedVolume()` and
`Body::ApplyBuoyancyImpulse()`, including a submerged centroid used
for torque. Cgame previously had this precision for convex polygons,
spheres and upright capsules, but its common **BoxShape3D** still
estimated immersion from the *world AABB's height*.

A box rotated relative to the water surface is not shaped like its world
AABB. The old approximation overestimates its displaced volume, moves
the center of buoyancy and can incorrectly make a heavy tilted box float.

## Exact geometry, limited CPU and no allocations

The helper `servers/physics_fluid_box_3d.h` divides a box into **six
fixed tetrahedra** along its 0-to-7 local-space diagonal. For a horizontal
water surface, it reuses Cgame's tested convex polyhedron/tetra clipping
and first-moment accumulator. All clipping happens in local coordinates;
a single absolute basis determinant converts geometric volume to world
units. Finally the submerged centroid is transformed into world space.

This accepts arbitrary box rotation, reflection, shear, nonuniform scale,
translation, and any horizontal water level without building or caching
a convex mesh. The temporary arrays live on the stack, so no heap and
no per-body memory additions are required.

The eight box corners are tested first. Completely dry and fully wet
boxes return **without clipping tetrahedra**. When fully submerged, the
center of buoyancy is exactly the box center. Invalid dimensions or
singular/overflowing transforms retain the previous approximate
AABB calculation rather than introducing invalid force values.

`modules/godot_physics_3d/godot_body_3d.cpp` passes the returned
geometrical submerged volume and center into the existing Archimedes
force, off-center buoyancy torque, quadratic fluid drag and angular
damping. The total volume of a shape is corrected to the exact box
volume for submerged-fraction damping when needed.

The advanced water plane remains opt-in via
`physics/3d/fluid_plane/enabled`, **false by default**. No changes to
the separate Jolt backend, public scripting APIs or rigid collision
solver.

## Reference values

A `2×2×2` box has volume 8. With its center at y=0 and a water surface
at y=0, submerged volume is 4 and submerged center is (0, -0.5, 0).

Rotate it 45° about Z. Its submerged volume remains 4, but its center
moves to (0, **-sqrt(2)/3**, 0), about -0.47140452. The previous
AABB-height approximation places the centroid at -sqrt(2)/2
(about -0.7071), producing the wrong torque.

For a box rotated 30° about Z, centered at y=0.7, water surface y=0,
the submerged volume is about **1.02443 (12.805% of the box)** and
the center has x around -0.10967, y around -0.22201.
Its old AABB-based volume fraction is about 29.79%.

At mass 1, fluid density 0.6 and gravity 9.8, this true displaced
volume produces insufficient lift to float the box. The old AABB
fraction would incorrectly float it.

## Validation

- `tests/servers/test_physics_fluid_box_3d.cpp`: exact dry/full/quarter/
  half immersions, tilted 45° centroid, nonuniform scale, reflection,
  shear-induced centroid offset and invalid geometry.
- `tests/stress/physics_fluid_oriented_box_3d_regression.gd`: compares
  a tilted box to a **convex hull with identical eight vertices**, same
  mass and transform. Both must sink, have matching approximate linear
  buoyant acceleration and generate a restoring torque; a dry box
  provides a no-lift control. This would fail with the old AABB waterline.
- `tests/stress/test_physics_fluid_box_3d.py`: standard-library source
  contracts, six-tetra volume decomposition, known analytical cases,
  90k seeded uniform-box samples near the rotated-waterline case and
  36 more randomly sheared and rotated world-Y tests.
- An independent, vectorized Python reference over **25 random affine
  transforms × 150,000 uniform points** observed maximum absolute
  submerged fraction deviation ~0.00226 vs clipped-tetra calculation,
  consistent with Monte Carlo sampling error. The numerical model also
  recovered analytical cube and diamond values.

```bash
python3 -m unittest discover -s tests/stress \
  -p 'test_physics_fluid_box_3d.py' -v

./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path tests/stress \
  --script res://physics_fluid_oriented_box_3d_regression.gd
```

Build Cgame with `tests=yes` and run native `[Physics]` tests.

**Limitations:** This is exact box displacement under a *horizontal*
water plane, not a fluid solver with waves/pressure/viscosity fields.
Overlapping compound shapes are still counted independently; exact
union-volume buoyancy remains future work.

Native Godot compilation, the new headless script and actual
CPU/FPS/RSS benchmark runs still require validation on an available
build host. Mathematical and static checks do not imply a measured
runtime performance gain.
