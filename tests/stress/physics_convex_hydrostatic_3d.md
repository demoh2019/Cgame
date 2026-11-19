# Exact convex polyhedron hydrostatics for GodotPhysics 3D

## Motivation and reference

Jolt Physics exposes `Body::GetSubmergedVolume()` and
`ApplyBuoyancyImpulse()` to use the submerged volume and its centroid for
forces and moments. Cgame's opt-in 3D water plane already had exact
analytic sphere/upright capsule displacement, but its **convex hulls**
still used the fraction of their AABB height below the waterline and
their AABB's centroid. This can dramatically overestimate displaced
water and produce incorrect torque and float/sink decisions.

This change adds an **exact half-space clipping method for valid closed
convex polyhedral meshes**. No external source code is copied.

## Geometry and implementation

Cgame's `GodotConvexPolygonShape3D` already stores the vertex and face
polygons of a convex mesh. Its vertices' arithmetic mean lies inside
a valid convex hull. Fan-triangulate each face and form a tetrahedron
between each surface triangle and that interior reference point.
The tetrahedra exactly partition the convex hull, with no overlaps.

For each tetrahedron, clip against the world-horizontal fluid surface
`world_y <= surface_height` using the existing shape transform. The
result has one of five vertex classifications:

- No submerged vertices: no volume.
- All four submerged: entire tetrahedron.
- Exactly one submerged: a smaller tetrahedron from three cut edges.
- Exactly three submerged: entire volume minus the dry tip tetrahedron.
- Exactly two submerged: a six-vertex clipped wedge decomposed into
  three tetrahedra.

Each tetrahedron contributes its absolute determinant divided by six
to volume, and its centroid times volume to its **first moment**. The
submerged centroid is the sum of first moments divided by the submerged
volume. Intermediate accumulators are `double` for numerical precision.
The triangles and slicing happen in local shape coordinates, with the
water plane transformed relative to the shape, mitigating cancellation
for bodies far from the world origin. The world's volume Jacobian is
the absolute determinant of the shape's basis, so rotation, shear,
reflection and nonuniform scale are supported.

The exact sample supplies the existing per-body lift and drag pipeline,
and the centroid drives the off-center buoyancy torque. Critically the
fluid also uses the **actual geometric hull volume**, replacing the
bounding-box volume in the submerged-fraction angular damping ratio
for successful convex samples. No changes are made to existing rigid-body
mass/inertia properties or to non-water simulation paths.

## Runtime cost and fallback

This is a more complex physical effect and is active only when
`physics/3d/fluid_plane/enabled` is true (off by default). Existing
broadphase bounds reject dry shapes before clipping. When a convex hull
is a valid closed mesh of **4–512 vertices and 4–256 faces**, the cost
is O(number of face triangles). No heap, temporary mesh, persistent
per-body cache or per-contact allocation is needed.

Malformed hull indices, degenerate/invalid transforms and shapes over
this face/vertex budget return `false`, and the body retains the
previous AABB approximation instead of losing buoyancy. High-poly
water-heavy scenes should be benchmarked carefully; using the
AABB fallback for visually minor bodies is preferable to spending large
CPU on exact clipping.

This is **exact geometry for valid closed convex hulls under a horizontal
water plane**, not full computational fluid dynamics. It does not
handle overlapping child-shape volume without double counting,
pressure waves, currents varying spatially, or interacting fluids.
Non-convex shapes continue to use approximations. To handle overlapping
compound shapes exactly would require union-volume integration.

## Regression and verification

Native C++:
`tests/servers/test_physics_fluid_convex_hull_3d.cpp` tests
an axis-aligned cube, a 45-degree rotated cube, translation,
nonuniform scale, reflection, one/two/three wet corners in a tetrahedron,
completely dry/full tetrahedron, invalid mesh indices and face budget.

For a 2x2x2 cube half submerged, exact volume = 4 and its center of
buoyancy is (0,-0.5,0). For the same cube rotated 45 degrees around Z,
half the volume remains submerged but the center of buoyancy moves to
(0,-sqrt(2)/3,0).

Headless Godot:
`tests/stress/physics_convex_hydrostatic_3d_regression.gd`
builds a tetrahedron with AABB volume 8 and **actual volume 4/3**,
of which **7/8** is submerged. At fluid density 0.75 and mass 1,
the tetrahedron should **sink** because its buoyancy is only
0.875 of its weight. A physically full box with the same AABB should
**float**; the old approximate tetra calculation incorrectly made
it float too. Also exercises off-center buoyancy torque, a dry
control and a rotated hull.

Independent checks:
`tests/stress/test_physics_fluid_convex_hull_3d.py`
compares 1-, 2- and 3-submerged-corner analytic expectations to
30,000 independently sampled uniform tetrahedron points per case
and validates C++ source wiring. A separate Python reference model
has compared 20 random tetrahedra against 100k-point uniform samples
each, with worst observed volume-fraction difference roughly 0.0022;
this is stochastic sampling uncertainty, not compiled Godot results.

```bash
python3 -m unittest discover -s tests/stress \
  -p 'test_physics_fluid_convex_hull_3d.py' -v

./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path tests/stress \
  --script res://physics_convex_hydrostatic_3d_regression.gd
```

Compile Cgame with `tests=yes` and run native `[Physics]`
tests. Measure per-physics-step time, peak RSS and rigid-body
stability before claiming a production speedup. The Mac build
device was offline when authoring this patch, and native C++
compilation and the headless regression have not been run.
