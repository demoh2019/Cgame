# Cgame GodotPhysics 3D: partially submerged rigid-body fluid plane

## Goal and related physics engines

Jolt Physics offers `Body::GetSubmergedVolume` and
`Body::ApplyBuoyancyImpulse`, which use a displaced volume, center of
buoyancy, drag, current velocity and gravity to simulate rigid-body
interaction with fluid. This Cgame implementation adds an **opt-in,
horizontal fluid surface** to the built-in GodotPhysics 3D backend.

Cgame already has an independent `physics/3d/solver/fluid_buoyancy`
setting that subtracts a uniform fraction of gravity from each rigid body,
and uniform `fluid_linear_drag` / `fluid_angular_drag` settings.
Those are not substitutes for partial submersion or buoyancy torque. When
the new fluid plane is enabled, its displaced-volume lift replaces
the older uniform lift; the older uniform drag settings remain separately
available. No source code from Jolt or other engines was copied.

## Settings

Enable the feature in Project Settings **before** creating the physics space:

| Property | Default | Effect |
|---|---|---|
| `physics/3d/fluid_plane/enabled` | `false` | Opt in to submerged rigid-body physics |
| `physics/3d/fluid_plane/surface_height` | `0` | Horizontal fluid surface, world Y (m) |
| `physics/3d/fluid_plane/density` | `1000` | Fluid density (project units: kg/m³ if units are SI) |
| `physics/3d/fluid_plane/drag_coefficient` | `0.8` | Quadratic drag coefficient |
| `physics/3d/fluid_plane/angular_drag` | `0.1` | Additional implicit angular damping per submerged fraction |
| `physics/3d/fluid_plane/flow_velocity` | `(0,0,0)` | Current velocity, world units/s |

Options are read and cached **once per physics space** at creation time,
so changing the Project Settings value does not instantly update an
existing physics space. The feature affects built-in GodotPhysics 3D;
the Jolt backend has its own body API and is not altered.

## Implementation

For each non-disabled shape of a dynamic 3D body (only when enabled):

1. Read its existing cached **world-space broadphase AABB** and
   world-scaled `get_shape_area(index)` (which represents volume in 3D).
2. Intersect the Y interval with the water half-space `y < surface_height`.
   Estimate displaced volume = actual shape volume × clipped AABB height ratio.
3. Estimate the submerged shape's center at the center of the clipped
   AABB region. Apply Archimedes' lift
   `F_b = -gravity × fluid_density × submerged_volume`.
4. Apply force at the estimated center of buoyancy, yielding torque
   `tau = (buoyancy_center - mass_center) × (lift + drag)`.
   This allows asymmetrically submerged rigid bodies to tilt and right
   themselves, unlike uniform gravity scaling.
5. Calculate local fluid-relative velocity including the rigid body's
   angular surface velocity and the configured current. Apply
   quadratic drag `F_d = -1/2 rho C_d A |v_rel| v_rel`, with projected
   AABB area `A`. Cap the explicit drag impulse per shape to avoid
   violent velocity reversal in dense fluids with large frame deltas.
6. Apply additional implicit angular damping proportional to the body's
   volume-weighted submerged fraction.

Zero additional per-body storage; the loop and a few temporary vectors
are executed only when the option is enabled. Static/kinematic bodies,
custom force integration, collision filtering, joints, CCD and contact
solving use their existing paths.

## Fidelity and limitations

**This is an approximate water-plane model, not an exact hydrostatic
solver.** The submerged fraction and center are estimated from the
world AABB of each shape, which is conservatively padded for broadphase.
Rotated objects, very thin concave objects, hollow geometry, and surfaces
with holes will have approximate waterline and torque behavior. Compound
shapes may also count overlapped volumes twice, as in simple additive
mass/inertia models. This version does not simulate pressure, waves,
viscosity gradients, hydrodynamic lift, per-area fluid volumes or
fluid-fluid interaction. Use the Jolt submerged polyhedron method or a
dedicated mesh clipping/voxel solver when precise displacement matters.

The water model is global per physics space, not linked to a visible
Water node or Area3D. Drag coefficients and density must be tuned to
the project's units and timestep.

## Tests and profiling

Native `tests/servers/test_physics_fluid_buoyancy_3d.cpp` checks
dry/partial/full submersion, center location, asymmetric buoyancy
torque, quadratic velocity scaling, stationary current, and stable
angular damping.

`tests/stress/test_physics_submerged_fluid_plane_3d.py` includes
**20,000** randomized volume and **8,000** randomized quadratic-drag
reference checks plus C++ source and ProjectSettings integration
contracts.

`tests/stress/physics_submerged_fluid_plane_3d_regression.gd` creates
three immersed/dry bodies and an asymmetrically submerged compound
body, enables a moving current, then creates a fresh water-disabled
space to compare with legacy gravity. It checks floating, dry fall,
partial buoyancy, current drag, rotational torque and disabled behavior.

```bash
python3 -m unittest discover -s tests/stress \
  -p 'test_physics_submerged_fluid_plane_3d.py' -v

./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path tests/stress \
  --script res://physics_submerged_fluid_plane_3d_regression.gd
```

Build Cgame with `tests=yes` and run native `[Physics] Fluid`
tests. A separate lightweight Python numerical reference for 28,000
inputs **passed** before this PR; this is not a substitute for native
compilation. The newly added engine/GDScript tests and realistic
CPU/RAM/FPS benchmarks have not been executed on a built engine in
this session.
