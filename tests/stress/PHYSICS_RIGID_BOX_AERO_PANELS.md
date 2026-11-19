# Cgame — oriented six-panel rigid-body box aerodynamics

## Background / comparison

Current Cgame GodotPhysics3D supports fluid buoyancy, approximate
isotropic quadratic drag and gyroscopic dynamics. Deformable bodies
also have aerodynamic interactions in their separate solver. Rigid
**BoxShape3D** collision geometry, however, has not had independent
pressure/skin forces evaluated at its oriented faces, and consequently
does not produce wind torque or angular skin damping from those panels.

Jolt exposes **force/impulse at a world-space position**, including
the corresponding torque; that is a useful integration pattern. Cgame
already applies external forces/torque. Here Cgame gains a new
**independent deterministic six-face numerical model**, not copied
from Jolt, Bullet or PhysX.

Reference:
- Jolt BodyInterface AddForce / AddImpulse at position
  https://jrouwe.github.io/JoltPhysics/class_body_interface.html

## Physical model

For every active dynamic RigidBody3D with a BoxShape3D, transform
the box's 3 local half-extent axes \`(hx,0,0)\`, \`(0,hy,0)\`,
\`(0,0,hz)\` by the **full world affine basis** (body * shape).
The cross product of the two axes parallel to a face defines its
true outward unit normal and area, even for a tilted, mirrored,
nonuniformly scaled or sheared box. Each axis provides one pair of
opposite faces, giving **six** face-center samples.

For a face with world center \`x_f\` and outward unit normal \`n\`:

    r = x_f - x_COM
    u = v_COM + omega × r - wind
    u_n = dot(u,n)
    u_t = u - u_n*n
    A = 4*length(cross(half_axis_j, half_axis_k))

    F_pressure = -0.5*rho*C_pressure*A*max(u_n,0)^2*n
    F_skin = -0.5*rho*C_skin*A*length(u_t)*u_t
    F = F_pressure + F_skin

- **One-sided pressure** acts on a face moving outward into the
  ambient medium. Its force is inward; static or shielded leeward
  faces receive no panel pressure. Back-face wake suction is not
  modeled, so calibrated physical drag coefficients are still needed.
- **Quadratic tangential skin drag** acts on the two-sided relative
  tangential velocity at the face centers. It causes resistance to
  translation and can damp a spinning box via torque.
- Both components satisfy \`dot(F,u) <= 0\` for stationary wind,
  so they remove (rather than inject) instantaneous local kinetic
  energy in the absence of other forces.
- A force applied at offset \`r\` changes **both** COM translation
  and body angular velocity. This is important for a sail-like
  box with the center of mass offset from its collision box, or
  for compound shape arrangements.

The force is translated into an impulse over dt and applied to
temporary velocity states. To avoid explicit Euler reversing
velocity along the resisting direction at coarse dt, the impulse
is capped using the physical directional effective inverse mass:

    direction = F / |F|
    k = m_inv + (r × direction) · I_world^-1 · (r × direction)
    opposing_speed = -dot(u, direction)
    J = min(|F|*dt, max(0,opposing_speed)/k)

    v_next = v + m_inv * direction * J
    omega_next = omega + I_world^-1 * (r × (direction*J))

The **updated temporary** velocities are used by the next face
(Gauss-Seidel), maintaining local kinetic-energy dissipation for
the positive-definite inertia case. A single face cannot reverse
the velocity component along its own resisting impulse. This is
a stability guard and **not** a globally implicit multi-body
aerodynamics solver.

Processing order: \`+X, -X, +Y, -Y, +Z, -Z\` in box-local axes.
The helper is transactional: invalid shape geometry or arithmetic
aborts the entire box step without changing either velocity.

## Settings — ProjectSettings

The model is **completely disabled by default**. Example:

    physics/3d/solver/rigid_box_aero_pressure_coefficient = 1.0
    physics/3d/solver/rigid_box_aero_skin_coefficient = 0.05
    physics/3d/solver/rigid_box_aero_density = 1.225
    physics/3d/solver/rigid_box_aero_wind_velocity = Vector3(5,0,0)

| Name suffix | Default | Purpose |
| --- | ---: | --- |
| pressure_coefficient | 0 | Windward pressure drag; [0,10] |
| skin_coefficient | 0 | Two-sided quadratic surface skin drag; [0,10] |
| density | 1.225 | Air density kg/m³, [0,2000] |
| wind_velocity | (0,0,0) | Uniform medium velocity m/s, world-space |

All settings are cached by the physics space. Non-finite scalars
and vectors are rejected/replaced with safe defaults. A coefficient
value of **0** disables that component. The fast path exits before
any new shape traversal when both coefficients are zero or density
is zero.

## Runtime and performance characteristics

- Applied **after** existing force/gravity/buoyancy, gyroscopic
  integration and uniform fluid velocity drag but before the
  existing speed/CCD caps, so speed limits can still catch outliers.
- Skips static/kinematic bodies, disabled shapes and all shape
  types except BoxShape3D. Does not allocate anything per shape.
- Complexity: **O(box collision shapes)** per dynamic body per
  tick, with at most 6 face-center evaluations and deterministic
  updates for each eligible shape.
- Uses actual world COM, world inverse inertia tensor and spin at
  each panel center. Does not merely sum a center-applied drag.
- Supports compound rigid bodies and valid affine box transforms.
  Extreme/singular transforms are rejected.
- Computes and validates both output velocities before committing
  them. Other shapes and bodies remain intact on a failed box step.
- Model can **add** to the existing uniform and water-plane drag.
  For clean aerodynamic benchmarks disable those other drag effects
  to avoid double-counting, unless the combination is intentional.

## Limitations and physical scope

This model is deliberately a low-cost **quadratic six-panel drag
approximation**, not the Navier–Stokes equations. It does not
simulate pressure wakes, vortex shedding, Reynolds-dependent
drag, wing lift, turbulent mixing, aerodynamic interaction between
nearby objects, occlusion by other colliders, moving water surface
fraction, hydrodynamic added mass or an actual sail pressure field.
Panel-center quadrature can miss torque on slender beams or complex
shapes. It is not an airfoil solver and does not replace specialized
vehicle/aerodynamics tools.

Wind is a per-space constant configured in ProjectSettings. For
time-varying wind, turbulence or aerodynamic materials per body a
future runtime physics-server API is required.

## Tests and merge gate

Independent Python numerical and source contracts:

    python3 -m unittest discover -s tests/stress \
      -p test_physics_rigid_box_aero_panels_3d.py -v

Native C++ doctests:

    scons platform=linuxbsd target=editor dev_build=yes tests=yes -j4
    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
      --test-case="[PhysicsBoxAero]*"

The **23 native C++ test cases** cover exact axial pressure (cube,
rectangular prism), sign and Galilean invariance, wind matching,
density and coefficient scaling, coarse timestep cap, offset
center-of-mass torque, world inverse inertia, surface skin drag
and rotational damping, reflected and rotated boxes, affine shear,
energy dissipation over many steps, invalid geometry/material and
overflow atomicity. The **20 Python tests** include an independent
mathematical panel oracle and integration source checks.

Before merging:

- Run a native Godot build and all the C++ doctests.
- Make a dynamic tilted BoxShape3D sail with non-zero lateral
  center-of-mass offset, steady crosswind, and a rigid support or
  wall. Compare no/weak/strong air density.
- Compare trajectories and spin at 60, 120 and 240 physics Hz,
  including high wind and small-mass bodies. Check no NaNs.
- Verify body sleeping/waking, CCD, mixed box/sphere compounds,
  all three axis locks and fluid/water-plane combinations.
- Benchmark 1k/10k/100k active boxes (p50/p95 CPU, RAM); verify
  no new allocations or measurable overhead with both coefficients 0.
- Rebase onto latest develop and resolve conflicts before merging.

The feature is experimental and should stay opt-in until those
native and scene benchmarks pass.
