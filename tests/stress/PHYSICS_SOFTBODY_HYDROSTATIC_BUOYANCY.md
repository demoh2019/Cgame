# Hydrostatic buoyancy for sealed GodotPhysics3D SoftBody3D

## Gap and reference

Jolt Physics currently documents buoyancy for soft bodies as not implemented.
PhysX offers GPU FEM deformables, but porting a full FEM/GPU fluid solver would
not fit this incremental, CPU-only engine change.

Cgame already supports a horizontal fluid plane, density and drag for rigid
bodies, as well as XPBD soft-body closed-volume topology validation. This
feature integrates those capabilities to produce **distributed water-pressure
forces on deformable triangular surfaces**, rather than applying one force
at a rigid body's bounding-box center.

## Enable

Use the GodotPhysics3D backend, set Project Settings before creating the space:

- physics/3d/fluid_plane/enabled = true
- physics/3d/fluid_plane/soft_body_hydrostatic_buoyancy = true (default false)
- physics/3d/fluid_plane/surface_height = 0.0 meters
- physics/3d/fluid_plane/density = 1000.0 kg/m³

This feature is independent of soft_body_xpbd_volume_compliance and existing
air drag/pressure. Recreating the space/soft body is needed to revalidate
topology after changing settings.

## Algorithm and physical interpretation

For each closed, consistently oriented triangle mesh:

1. Validate manifold edges during existing soft-body rest-volume setup. A
   closed oriented edge occurs exactly twice with opposite direction. Validate
   non-degenerate enclosed volume and save its sign for inward/outward meshes.
2. At each physics step, if gravity points down world -Y and water is enabled,
   clip each surface triangle against y <= surface_height, using a stack-only
   Sutherland-Hodgman clipping pass. A clipped triangle creates up to four
   vertices, triangulated into one or two subtriangles.
3. Hydrostatic pressure is p(y) = density * |gravity.y| * max(0, H-y).
   Integrate pressure times each original vertex barycentric shape function
   exactly (both are linear on each clipped subtriangle):
       integral_triangle(pressure * bary_i) =
           area/12 * (sum_pressure * sum_bary_i +
                      sum_over_vertices(pressure_j * bary_i_j))
4. Apply -pressure * outward_normal to nodes. Pinned vertices remain fixed.
   Forces with invalid numerics are rejected before touching accumulators.

For a closed body, the total force obeys Archimedes law for its displaced
submerged volume (assuming coherent winding). Distributed forces also allow
hydrostatic torque when the body is partly tilted/immersed.

## Scope and limits

- **CPU only**, O(number of faces) time, O(1) stack scratch per triangle,
  zero persistent allocation when enabled. Default-off path has only a guard.
- Only sealed, consistently oriented triangle surfaces; *open cloth cannot
  displace a closed fluid volume* in this simplified model. Disconnected shells
  with opposite windings are not supported.
- Flat water surface and nearly vertical downward gravity only. No waves,
  two-way fluid coupling, finite-depth bathymetry, water flow, viscosity, fluid
  motion, atmospheric pressure, adhesion, cavitation, fluid particle contacts
  or fluid drag on soft bodies.
- No fluid behavior is added to Jolt backend or PhysicsServer3DExtension.
- Accurate for piecewise planar surface at the beginning of the physics tick.
  Very large water pressures can destabilize an explicit soft-body integrator;
  existing maximum per-frame speed clamp limits individual acceleration but
  not global stiffness. Use small fixed timesteps and limited density for
  small/light soft bodies.
- Mesh deformation that causes inversion/self-intersection can invalidate the
  manifold pressure interpretation; runtime faces are not re-topologized.
- All invalid inputs are guarded; a failing face is skipped with no partial
  force updates. Unsupported tilted gravity is skipped rather than applying
  a physically inconsistent hydrostatic column.

## Verification

Pure Python numerical and source contracts:

    python3 -m unittest discover -s tests/stress -p test_physics_softbody_hydrostatic_buoyancy.py -v

Native C++ doctest cases:

    scons platform=linuxbsd target=editor dev_build=yes tests=yes -j4
    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test --test-case="[PhysicsHydrostaticSoft]*"

C++ checks include completely submerged Archimedes tetrahedron, partially
submerged tetrahedron, dry body, barycentric pressure distribution,
translation/winding invariance, invalid and degenerate inputs, and zero
density/gravity.

**Before merging:** run native build and headless physical scenes comparing
a sealed rubber ball, a tilted tetrahedron and an open cloth sheet with the
feature enabled/disabled. Measure physics-step p50/p95 CPU, peak RSS and
water-entry stability on 1k / 10k / 100k face meshes. Tune timestep/solver
iterations; do not claim production-grade fluid simulation or proven speedup
based solely on contract tests.

## Relevant engine docs

- https://jrouwe.github.io/JoltPhysics/
- https://nvidia-omniverse.github.io/PhysX/physx/5.7.0/docs/DeformableBodyOverview.html
