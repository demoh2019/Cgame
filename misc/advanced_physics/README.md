# Cgame Advanced Physics Lab — water and wind (prototype)

Optional 3D physics extension for the Cgame/Godot fork. It uses the existing
`RigidBody3D` collision/constraint solver (including Jolt when selected) and
applies external forces in `_physics_process`. **It is not a new solver,
Navier–Stokes simulation, fluid-particle system, or a replacement for Jolt.**

## Features

- Archimedes buoyancy, `F = -rho * V_submerged * gravity`.
- Multiple shape samples with exact spherical-cap submerged **fraction and
  centroid** per probe; force application away from the body origin produces
  pitch and roll torques.
- Quadratic form drag plus low-speed Stokes viscous resistance, flowing water,
  and rotational drag.
- Spatial wind regions with quadratic aerodynamic drag, simple deterministic
  sinusoidal gusts, rotational damping, and opt-in Magnus lift.
- An explicit-step opposing-force limiter to reduce drag overshoot.
- Independent, headless mathematical regression tests.

The displacement volume, cross-section area, probe radius, and positions are
**user-configured approximations** of the actual mesh or collision shape.
The formulas are SI-unit models; shape sampling is a game-physics approximation.

## Quick start

Open `misc/advanced_physics` as a Godot 4 project and run the demo.
Alternatively copy `addons/advanced_physics` into any Godot 4 project's
`res://addons/advanced_physics` directory.

1. Add `RigidBody3D` with a `CollisionShape3D`.
2. Add a **direct child** `Node3D` to the body and attach
   `fluid_body_3d.gd`. Configure displaced_volume (m^3), drag_area (m^2),
   sample_radius (m), and sample_offsets (body-local positions in meters).
3. Add an `Area3D` to the scene with `water_volume_3d.gd` attached.
   Give it a `CollisionShape3D` covering the water region and set its
   collision mask to include the rigid body's collision layer.
   Set surface_height **in world-space Y coordinates**. Water is present
   only where the area overlaps the body; the mathematical surface is flat.
4. Optionally add another `Area3D` with `wind_volume_3d.gd`, plus a
   `CollisionShape3D` and matching collision mask. Set wind_velocity (m/s)
   and gust_amplitude (m/s).

The water component's `gravity_vector` should match the scene gravity.
The same body may be affected by several area volumes; overlapping forces are
additive, so avoid overlapping water regions unless that is intentional.

## Tests

```sh
godot --headless --path misc/advanced_physics --script res://tests/test_fluid_math.gd
```

The script exits with a nonzero status on failed assertions. The mathematical
tests cover exact cap fractions and centroids, Archimedes force, symmetric
torques, quadratic vs. linear drag, Magnus force, angular damping and
per-step drag caps. **Running these tests does not verify a C++ engine build
or a full physical scene.**

## Technical limitations and next milestones

- Only 3D `RigidBody3D`; no direct soft-body, cloth or rope coupling yet.
- Fluid volumes use an Area3D broadphase, not per-probe area/mesh clipping.
  A body entering the area may receive forces at probes beyond its bounds.
- Probe-based buoyancy is approximate for arbitrary meshes, especially thin,
  concave, porous, or rapidly changing shapes.
- Water is a horizontal plane with one density and current; no wakes,
  pressure field, surface tension, shallow-water solver, SPH/PBF, or
  bidirectional fluid feedback.
- Wind uses stateless drag and simplified Magnus lift, not vortex shedding,
  true airfoil stall, or CFD; exposed probe area is constant.
- Per-step damping is a safety measure, not a guarantee of unconditional
  stability with many overlapping fields or extreme body rotations.
- Needs live Godot headless scene tests, profiling with hundreds of bodies,
  Jolt/Godot-Physics parity checks, and continuous integration.

Design inspiration: Jolt's shape-aware submerged-volume/buoyancy API, MuJoCo's
phenomenological fluid-force models, and Bullet's separate soft-body pipeline.
No code copied from those libraries.
