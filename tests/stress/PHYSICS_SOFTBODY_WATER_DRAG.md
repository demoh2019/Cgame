# SoftBody3D: submerged current-relative drag (GodotPhysics3D)

## Motivation

Cgame already simulates two-sided air drag, lift and a flat water plane for
rigid bodies. Jolt's rigid-body buoyancy API combines water current and drag,
while Jolt's soft-body work-in-progress docs still list buoyancy as missing.
PhysX's advanced FEM deformables use GPU/CUDA, so this incremental CPU
feature focuses on a *specific missing material/environment force* rather
than replacing the solver.

This adds quadratic underwater fluid resistance for open cloth and closed
deformable meshes, including partially submerged faces and moving water.
It does not depend on the closed-body hydrostatic pressure draft PR #632.

## Enable (requires GodotPhysics3D)

In Project Settings, before creating the physics space:

- physics/3d/fluid_plane/enabled = true
- physics/3d/fluid_plane/soft_body_water_drag = true (default false)
- physics/3d/fluid_plane/surface_height = water surface, world Y, meters
- physics/3d/fluid_plane/density = water density (default 1000 kg/m³)
- physics/3d/fluid_plane/drag_coefficient = normal Cd (default 0.8)
- physics/3d/fluid_plane/soft_body_water_tangential_ratio = 0..5, default 0
- physics/3d/fluid_plane/flow_velocity = water velocity in world space (m/s)

Ratio zero models two-sided form/normal drag only. A positive ratio adds
quadratic in-plane/skin drag. Flow velocity is subtracted from cloth
velocity: a current pushes resting cloth. Existing SoftBody3D air drag,
gas pressure and constraints remain separate.

## Solver details

1. Clip each deformable triangle against the world Y water surface via
   Sutherland-Hodgman. The wet polygon has at most four vertices and
   needs no allocation. Each clipped vertex retains its barycentric
   weights relative to the original triangle.
2. Triangulate the wet polygon. For each clipped subtriangle, compute
   its area, original face normal, interpolated relative centroid
   velocity, and mass-weighted effective inverse mass:
      inv_mass_eff = sum(w_i² * inv_mass_i)
3. Apply quadratic normal and optional skin drag with a bounded
   per-subtriangle implicit relaxation. With k = (rho * Cd * A / 2),
   speed magnitude u, step dt and effective inverse mass w:
      fraction = 1 - 1/(1 + k * |u| * dt * w)
      force_scalar = -u * fraction / (dt * w)
   The normal and tangential components are relaxed independently.
   This avoids one subtriangle reversing its centroid's relative speed
   even with high density, Cd or dt.
4. Distribute each subtriangle force to original nodes using the
   centroid barycentric weights. Pinned nodes (inverse mass 0)
   receive no velocity-changing force.
5. Validate all three output vectors before committing force
   accumulators; invalid/overflow values are rejected atomically.

For fully/partly immersed faces it requires O(faces) computations
without GPU or persistent scratch; only stack-local small arrays.
The water pass **shares the existing aerodynamic face traversal**,
avoiding a second traversal when air/wind or pressure is active.
With the default option disabled, no new clipping or water force
processing runs.

## Scientific limitations and engineering constraints

- This is a thin-surface hydrodynamic drag approximation using centroid
  quadrature per clipped triangle, not full Navier-Stokes, SPH, FLIP,
  shallow-water coupling, viscous Stokes flow, wave interaction, or
  vortex shedding.
- It runs for open cloth and closed soft surfaces but does not implement
  hydrostatic lift; use the separate sealed-shell pressure PR for that.
- The water plane is horizontal; no water waves, shoreline geometry, or
  spatially varying flow. Pressure-induced deformation is not covered.
- Current/backflow drag is evaluated using the velocity at the start
  of the step and integrated as a force for the existing solver. A
  subtriangle implicit relaxation can be applied multiple times by
  adjacent faces, so complete mesh stability and energy conservation
  are not proven. Extreme high-valence meshes and huge time steps
  require dedicated numerical evaluation.
- No shared-array allocation in the default-off path. There is O(1)
  temporary storage per face, but additional CPU when enabled.
- No contribution to Jolt backend / PhysicsServer3DExtension.
- The helper guards invalid geometry, timestep, mass and overflowing
  forces. Existing non-water wind/pressure force paths retain their
  own checks.

## Regression tests and performance gate

Source/numerical Python:

    python3 -m unittest discover -s tests/stress \
      -p test_physics_softbody_water_drag.py -v

Native editor with tests:

    scons platform=linuxbsd target=editor dev_build=yes tests=yes -j4
    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
      --test-case="[PhysicsWaterDrag]*"

Expected 9 C++ regression cases: dry/immersed faces, damping
stability, current-driven skin flow, tangent disabled, partial wet
area, pinned particles, winding reversal, zero coefficients and
nonfinite/degenerate inputs.

Before merge, run a headless open cloth scene falling into water and
a taut curtain in lateral current. Verify no NaNs, reasonable velocity
limits, and compare with a control scene while switching drag on/off.
Record physics step p50/p95 and peak RSS at 1k/10k/100k triangles,
fixed 60/120 Hz timestep, varying density and current. Require
successful native CI build and runtime scene regressions.

## References

- https://jrouwe.github.io/JoltPhysics/class_body.html
- https://jrouwe.github.io/JoltPhysics/
- https://nvidia-omniverse.github.io/PhysX/physx/5.7.0/docs/DeformableBodyOverview.html
