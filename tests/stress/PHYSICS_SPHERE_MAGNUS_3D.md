# Opt-in Magnus spin lift for GodotPhysics3D spherical rigid bodies

## Why this exists

Cgame has buoyancy, quadratic fluid drag, rolling/spinning contact
friction and torque-free gyroscopic integration. **None** of these
models the lateral force from spin and airflow around a traveling
ball, the **Magnus effect**. Jolt exposes force-at-position and torque
on rigid bodies; Cgame's GodotPhysics3D force/torque path now adds
this missing interaction to real spherical collision shapes, with
an independent, small numerical kernel and no copied code.

This is **phenomenological sphere aerodynamics**, not a generalized
vortex-flow Navier-Stokes model. No lift is generated for boxes,
capsules, arbitrary convex hulls, scaled ellipsoids, soft bodies or
kinematic bodies.

## Constitutive model

For each enabled, uniformly scaled SphereShape3D in a moving rigid
body, with sphere world center x and body world center of mass x_com:

    lever = x - x_com
    u = v_com + omega × lever - wind
    S = omega × u
    A = pi * R^2                  # true spherical cross-section
    raw_CL = C_spin * R * |S| / |u|^2
    CL = min(raw_CL, CL_max)
    F = 0.5 * rho * A * CL * |u|^2 * normalize(S)
    torque_com = lever × F

This is evaluated in numerically equivalent form

    F = 0.5 * rho * pi * R^2 * min(
          C_spin * R,
          CL_max * |u|^2 / |S|
        ) * S

to avoid unnecessary normalization and yield a smooth, linear-in-spin
force below the lift cap.

\`rho\` is fluid/air density in kg/m³; \`R\` is the sphere's
**actual world-space radius**. Every force has dimensions Newtons.
The rigid-body integrator divides the summed force by mass, and
applies the lever-arm torque through the world inverse inertia tensor.

Physical properties:

- \`F\` is perpendicular to the relative flow **at the sphere center**
  (\`F · u = 0\`), so it does not directly add/remove kinetic energy
  in continuous motion at that point; discrete Euler integration
  can still introduce small numerical energy drift.
- \`F\` is perpendicular to angular velocity.
- Reversing spin reverses lift; reversing flow reverses lift.
- A uniform Galilean change to both object and ambient medium
  leaves the force unchanged.
- Uncapped lift scales with \`rho * R³ * omega * u\`.
- A large spin ratio is bounded by the dynamic-pressure model
  \`|F| <= 0.5*rho*A*CL_max*|u|²\`.

The shape integrator additionally caps the **per-step lateral impulse**
from each sphere by \`mass * |u| / max(1, shape_count)\`. This is a
numerical guard for very light compound bodies and extremely large
physics timesteps, not a calibrated aerodynamic law.

Spheres with nonuniform scale/shear are **skipped**. A sphere
transformed by an orthogonal uniform scale is still a sphere and
uses the scaled radius. Only enabled collision shapes are considered.

## Settings (ProjectSettings / GodotPhysics3D)

At the project level, set **before creating the physics space**:

    physics/3d/solver/sphere_magnus_spin_coefficient = 0.3
    physics/3d/solver/sphere_magnus_medium_density = 1.225
    physics/3d/solver/sphere_magnus_max_lift_coefficient = 1.5
    physics/3d/solver/sphere_magnus_flow_velocity = Vector3(0, 0, 0)

- \`spin_coefficient\` default **0** disables all new work.
  Validated range [0,10], dimensionless; not a directly measured
  \`C_L\`, which also depends on the spin parameter \`omega*R/|u|\`.
- \`medium_density\` default **1.225 kg/m³** (approximate air),
  validated [0,2000]. Can approximate denser media but the
  underlying \`C_L\` model may not apply to real underwater flow.
- \`max_lift_coefficient\` default **1.5**, range [0,5].
- \`flow_velocity\` default **(0,0,0) m/s** in world coordinates.
  This is separate from existing \`fluid_flow_velocity\` and water
  plane flow, to avoid accidental cross-coupling.

Suggested scene: a RigidBody3D with a single SphereShape3D, initial
velocity (10,0,0) m/s and spin (0,0,100) rad/s; the force bends
the trajectory toward +Y with the model's coordinate convention.
Reverse the spin to bend toward -Y. This **is not** a runtime demo
scene; it is a proposed validation arrangement.

## Costs and backward compatibility

- Default \`spin_coefficient = 0\`: **no new shape traversal, force,
  torque or allocated buffers**. Off-path only evaluates a boolean
  condition in existing rigid-body force integration.
- Enabled: O(number of enabled collision shapes) per dynamic rigid
  body and step; no allocs per shape. Only the sphere shapes proceed
  to the cross-products and double-precision force calculation.
- Skips kinematic/static bodies and scenes where custom integration
  suppresses the engine's force step.
- Does not alter gyroscopic integration, external forces, fluid plane
  buoyancy, friction constraints, collision manifold topology or
  material properties.
- Compound bodies receive physically consistent torque from their
  offset spherical shapes. Every shape's center uses
  \`linear_velocity + angular_velocity × lever\`, not merely the COM
  speed.

## Tests

Python analytical/source tests:

    python3 -m unittest discover -s tests/stress \
        -p test_physics_sphere_magnus_3d.py -v

Native C++ doctests:

    scons platform=linuxbsd target=editor dev_build=yes tests=yes -j4
    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
        --test-case="[PhysicsMagnus]*"

19 native C++ cases validate the force direction, sign symmetry,
Galilean invariance, zero/parallel spin, density and R³ scaling,
unsaturated spin scaling, dynamic-pressure lift limit, high-speed
safety, offset-shape torque, and invalid-input transactional behavior.
18 Python cases include independent numerical oracles and checks
that the real GodotPhysics3D integrator actually calls the model.

**Before merging:** run headless 3D flight scenes comparing positive
and negative spin with otherwise identical initial conditions at
60/120 Hz. Plot lateral displacement, kinetic energy, max force,
max angular speed and nonfinite counts. Include a sphere attached
off-center to a larger body, a nonuniform-scale sphere and collision
with a static wall. Measure per-step cost with 1k/10k/100k moving
spheres and ensure default-off overhead is negligible.

## Limitations

A proper wind-tunnel-calibrated sphere model depends on Reynolds
number, turbulence, drag crisis, surface roughness and spin-dependent
\`C_L\`; this helper intentionally does not. There is no dynamically
coupled wake, pressure distribution, fluid back-reaction, submerged
fraction for partially immersed balls, air drag coefficient update,
or GPU particle/vortex coupling. The lift field is uniform for the
entire physics space, not a per-body material.

Background: Jolt BodyInterface supports applying force and torque
to rigid bodies at the point of application:
https://jrouwe.github.io/JoltPhysics/class_body_interface.html
