# Cgame — opt-in rotating-reference-frame rigid-body dynamics

## Background

GodotPhysics3D in Cgame already contains advanced rigid-body gyroscopic
precession, fluid drag, buoyancy, contact friction and CCD. However, it
integrates linear center-of-mass velocity in a stationary simulation frame.
It has no option to model **a world viewed from a prescribed rotating
reference frame**: for example the floor of a centrifuge or a rotating
space habitat.

This patch adds the **non-inertial translational equations** to
**dynamic RigidBody3D COM velocity**, without copying other engines'
code. This is a targeted enhancement to Cgame's existing rigid-body
integrator, restricted to **COM translation only**, using established
rotating-frame mechanics and an energy-
preserving Boris/Cayley step for the Coriolis part.

It is not a complete rotating-world transform or generalized rotating
rigid-body equations for the orientation, contacts and constraints.

## Physics model

Relative position in the rotating frame:

    r = x_COM - frame_origin

Given frame angular velocity Ω, frame angular acceleration α, and
the body's velocity v **expressed in this rotating frame**:

    dv/dt = a_physical
            - 2 Ω × v                # Coriolis
            - Ω × (Ω × r)             # centrifugal
            - α × r                   # Euler

- **Coriolis:** perpendicular to velocity; changes direction but does
  no instantaneous work (\`v · a_coriolis = 0\`).
- **Centrifugal:** outward from the rotation axis; vanishes when
  \`r\` is parallel to \`Ω\`. It can change kinetic energy, and
  corresponds to the usual centrifugal potential.
- **Euler:** appears when the rotation rate itself changes. This is an
  **instantaneous** prescribed angular acceleration; Cgame does not
  automatically evolve the configured frame Ω between physics steps.
  Continuous spin-up needs an additional runtime angular-frame API.

The ordinary engine already applies physical force, gravity,
buoyancy and drag to linear velocity; **after those** updates, this
patch applies a fictitious-acceleration step. The fictitious terms
are per unit mass, so there is no extra \`F/m\` factor. Rigid COM
position is sampled at the beginning of the step (frozen), matching
the existing force integration convention.

### Stable integrator

Define frozen centrifugal/Euler acceleration

    A = |Ω|²*r - Ω*(Ω·r) - α×r

and use two half kicks around a Boris/Cayley velocity rotation:

    v_minus = v + 0.5*dt*A
    t = Ω*dt
    s = 2*t/(1 + |t|²)
    v_prime = v_minus + v_minus×t
    v_plus = v_minus + v_prime×s
    v_next = v_plus + 0.5*dt*A

This is second-order symmetric splitting for a constant \`A\` and
the exact **Cayley** update for the Coriolis part. At zero
centrifugal and Euler acceleration it preserves \`|v|\` up to
rounding, including when \`|Ω|*dt\` is large. Its **rotation
phase is approximate**, not the exact \`2|Ω|dt\` phase:
smaller dt is still needed for precise trajectories.

This avoids the unphysical energy growth from simply integrating
Coriolis through explicit Euler, where

    |v + dt*(-2Ω×v)|² > |v|²

for nonzero perpendicular velocity.

The C++ numeric helper uses double intermediates even in float32
Godot builds, rejects nonfinite/overflowed outputs and commits
all three velocity components at once. No per-body allocations.

## Configuration

ProjectSettings, before creating the GodotPhysics3D space:

    physics/3d/solver/rotating_frame_enabled = true
    physics/3d/solver/rotating_frame_origin = Vector3(0,0,0)
    physics/3d/solver/rotating_frame_angular_velocity = Vector3(0,0,2)
    physics/3d/solver/rotating_frame_angular_acceleration = Vector3(0,0,0)

Defaults: **false**, origin=(0,0,0), angular velocity=0,
angular acceleration=0.

- \`rotating_frame_enabled\`: opt-in, prevents any behavior change
  and all extra math by default.
- \`rotating_frame_origin\`: center of rotation in the simulation's
  world coordinates, validated finite, invalid -> (0,0,0).
- \`rotating_frame_angular_velocity\`: angular frame velocity,
  rad/s, world-frame components validated and capped individually
  to [-100, 100].
- \`rotating_frame_angular_acceleration\`: instantaneous dΩ/dt,
  rad/s², similarly clamped to [-100, 100] per component. Does
  **not** update Ω automatically between simulation steps.

A moving object at v=(1,0,0) with Ω=(0,0,1), at the frame's axis,
and with dt=0.1 has after one pure Coriolis step

    v_new ≈ (0.980198, -0.198020, 0).

The speed is still 1, but the direction curves clockwise when
viewed along positive Z. At the axis a **stationary** body remains
stationary without other forces; two meters away from the Z axis,
it acquires a small radially outward centrifugal velocity.

## What changes / what does not

- Changes **only** the linear COM velocity of **dynamic rigid
  bodies**, via \`GodotBody3D::integrate_forces()\`.
- Affected only when built-in force integration is active. Bodies
  using custom \`_integrate_forces\` suppression, kinematic and static
  bodies remain unaffected. This prevents unexpected changes to
  externally controlled motion.
- Does not modify rigid body's angular velocity, orientation,
  gyroscopic integration, inertia, contacts, pinning, CCD geometry,
  gravity/area calculation, forces on other bodies or any soft body.
- Does not rotate the coordinate axes, static level geometry,
  camera, constraints or the scene itself. The developer must
  author/render the surrounding geometry consistently **in frame
  coordinates**, or the simulation will not represent a physically
  rotating laboratory.
- Rotating bodies with anisotropic inertia require additional
  non-inertial angular-momentum terms; this patch models **COM
  translation only**, not fully frame-covariant 6-DOF dynamics.
- Centrifugal force can become very large at high Ω or long
  distances. Use small fixed physics steps, sensible angular
  velocity and the existing optional maximum speed/CCD settings.
- For a true spinning frame with evolving Ω, project-level cached
  configuration is a snapshot. A future per-space runtime frame API
  would be required for time-varying spin.

## Computational cost / backwards compatibility

- Disabled: one boolean conditional during existing force integration
  on dynamic rigid bodies, **no new per-body buffers or passes**.
- Enabled: O(1) arithmetic and two 3-vector cross products per
  dynamic body per step, using double intermediate math.
- No new allocations, mesh scans, broadphase queries or extra
  solver iterations. Physics-space parameters are cached at setup.
- Direct forces, friction, linear and angular damping all remain
  on the historical path with the feature disabled.

## Verification

Python independent numerical oracle + source contracts:

    python3 -m unittest discover -s tests/stress \
      -p test_physics_rotating_frame_3d.py -v

Native C++ doctests:

    scons platform=linuxbsd target=editor dev_build=yes tests=yes -j4
    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
      --test-case="[PhysicsRotatingFrame]*"

The 20 C++ cases cover pure Coriolis orientation, Boris speed
conservation over 100 updates and extreme dt, sign reversal,
inversion by reverse spin, axial motion, centrifugal sign and
quadratic scaling, Euler spin-up reversal, relative-origin
translation, mixed-3D finite checks and atomic failure.

The 18 Python cases independently reconstruct the analytic law,
verify dot products/orthogonality, time symmetry, centripetal axis
invariance, numeric guards and GodotPhysics3D wiring.

### Before merging

Run a headless rotating-disk / spinning-habitat scene with dynamic
spheres and fixed walls in the same frame coordinates:
- Compare experimental Coriolis trajectories with analytic
  \`cos(2*Omega*t)\` and \`sin(2*Omega*t)\` for small dt.
- Verify centrifugal outward drift and zero drift on the axis.
- Check pure Coriolis kinetic energy, substep consistency and
  contact impulse stability at 60/120/240 physics FPS.
- Compare disabled vs enabled p50/p95 integration cost and peak
  RAM for 1k/10k/100k awake rigid bodies.
- Exercise area gravity, gyroscopic asymmetric rigid bodies,
  CCD, high angular-speed caps and custom-integrated bodies.
- Verify both float32 and double precision configurations.

## References

- MIT OpenCourseWare, *Non-Inertial Linear and Rotating Reference Frames*:
  https://ocw.mit.edu/courses/8-01sc-classical-mechanics-fall-2016/mit8_01scs22_chapter31.pdf
- University of Zürich, *Non-inertial frames and pseudo forces*:
  https://www.physik.uzh.ch/dam/jcr%3Ab9da5e7c-c0d0-4cd2-82ff-323894590c06/Physics-1-Kilminster-2023.v1.pdf
- Boris method, Cayley energy-preserving rotation (plasma integration):
  https://epub.uni-regensburg.de/36198/1/DVilsmeier-IPMSimulations.pdf
