# Closed SoftBody3D bulk viscosity (volume-rate damping)

GodotPhysics3D now supports **opt-in global volumetric viscosity** for
closed, oriented soft bodies. This damps breathing/compression oscillation
without damping free translation, rotation, or ordinary shear.

It builds on velocity-level damping and volume constraints in XPBD,
Bullet deformables and PhysX FEM materials. This is a closed-shell
velocity constraint, **not** a tetrahedral FEM constitutive model.

## Enable

Project Setting:

\`physics/3d/solver/soft_body_volume_damping_rate = 3.0\`

- Units: 1/second. Default 0, no extra face passes or scratch storage.
- Requires a closed, consistently oriented manifold mesh (open cloth skipped).
- Works without enabling XPBD volume compliance or gas pressure.
- Pinned vertices do not move. Reaction is absorbed by attachments.
- The existing XPBD volume-gradient buffer is reused and kept across steps.

## Mechanics

\`Vdot = Σ g_i·v_i\`, where \`g_i = ∂V/∂x_i\`.
Pinned vertices contribute no velocity.
\`K = Σ w_i |g_i|²\`, where \`w_i\` is inverse mass.
\`f = 1-exp(-rate*dt)\`.
\`λ = -f Vdot / K\`.
\`v_i ← v_i + w_i g_i λ\`.

Thus \`Vdot_after = (1-f)Vdot_before\`. Kinetic energy decreases by
\`f(2-f) Vdot² / (2K)\`; free-body linear and angular momentum are
preserved because the closed-shell volume gradients sum to zero and
their torque sum is zero.

Runs once before position prediction. The velocity update uses a
two-phase commit to avoid partial updates if a corrupted input would
overflow a floating-point value. Complexity is O(faces + vertices)
when enabled.

## Validation

C++ doctest: \`tests/servers/test_physics_softbody_volume_damping.cpp\`

Python: \`python3 -m unittest discover -s tests/stress -p 'test_physics_softbody_volume_damping.py' -v\`

Includes 30,000 randomized energy and rate contracts, 2,000 momentum
cases, timestep subdivision, pins and source integration checks.

## Limits

Unlike true tetrahedral FEM bulk viscosity this is one global volume
mode. Meshes with multiple interior deformation modes require local
tetrahedral volume damping. The feature affects built-in GodotPhysics3D,
not the Jolt backend.
