# Cgame — local tetrahedral volumetric viscoplasticity

Cgame GodotPhysics3D supports an experimental **per-element permanent
volumetric deformation** model for cooked convex tetrahedral FEM shells.

Inspired by continuum mechanics: additive *logarithmic volume strain*
and a simple rate-dependent isotropic plastic rest configuration. This
extends the existing Neo-Hookean/Mooney–Rivlin FEM, per-element damage,
fiber reinforcement, Kelvin–Voigt viscosity and global closed-shell
viscoplastic volume constraint. It is not multiplicative finite-strain
J2 metal plasticity, yield-surface return mapping, cracking or dynamic
tetrahedral remeshing.

## Enable

Project Settings:

\`physics/3d/solver/soft_body_tetra_fem_compliance = 0.00001\`

\`physics/3d/solver/soft_body_tetra_volume_plastic_rate = 2.0\`

\`physics/3d/solver/soft_body_tetra_volume_plastic_yield = 0.15\`

The new plastic **rate defaults to 0**, preserving the existing FEM
behavior. The yield is a dimensionless logarithmic volume strain, not
an absolute world-unit volume or Young's modulus.

## Mechanics

Each FEM tetrahedron retains its own scalar total plastic-volume ratio
\`Vp/Vp0\` (one additional double per cooked tetra), initially 1.

Relative to the current *mechanical* rest state, let

\`J = det(current_edge_matrix) / rest.signed_det\`, \`e = ln(J)\`.

When \`|e| > yield\`:

\`f = 1 - exp(-rate * dt)\`

\`dlogVp = f * sign(e) * (|e| - yield)\`

\`newVp = clamp(Vp * exp(dlogVp), 0.2, 5.0)\`

For \`q = newVp/Vp\`, update the tetra rest state ATOMICALLY:

- \`rest.volume *= q\`
- \`rest.signed_det *= q\`
- \`rest.inv_dm /= cbrt(q)\`

This is an **isotropic** local rest-frame plastic deformation: tensorial
shear plasticity is not represented. At constant deformation, the
remaining elastic volume strain relaxes exponentially into the
threshold band and the time subdivision is stable. Unloading leaves
the deformed rest state, rather than recovering the original.

The update runs **once per physics tick on predicted positions**,
before XPBD elastic projection and after local FEM velocities are
integrated. Pinned vertices and simulated node positions are untouched
by the plastic update; forces arise in subsequent elastic iterations.

## Compatibility / limitations

- Works with both available FEM elastic models: Neo-Hookean and
  Mooney–Rivlin. Fiber rest-frame calculations inherit the changed
  isotropic rest matrix. The existing local damage scalar remains
  independent.
- Closed-shell gas pressure continues to reference the immutable
  initial volume; the global XPBD volume target also remains distinct.
- The volume-weighted nodal masses are cooked from the ORIGINAL mesh
  and do not change if the plastic rest state evolves (mass is conserved).
- Existing strict convex-shell tetrahedral cooking limitations apply.
  No concave bodies, holes, interior tetrahedral mesh import, or new
  fracture topology.
- Inverted/near-collapsed and invalid meshes cannot undergo plastic
  rest changes; opt-in FEM inversion recovery handles inversion first.
- Accumulated plastic rest-volume ratio is capped to 20%-500% of the
  initial element to avoid zero/infinite rest matrices.
- No per-timestep allocations; zero default rate skips the extra
  O(number_of_tetrahedra) solver pass completely.

## Verification

C++ doctest:
\`tests/servers/test_physics_fem_tetra_volume_plasticity.cpp\`

Independent standalone compile/run of the actual C++ helper with
float32 and float64 \`real_t\`:
\`tests/stress/test_physics_fem_tetra_volume_plasticity_compiler.cpp\`.

Numerical and engine source integration contracts:
\`python3 -m unittest discover -s tests/stress -p 'test_physics_fem_tetra_volume_plasticity.py' -v\`.

Next development: local tensorial plastic deformation gradients, von
Mises / Drucker-Prager yield surfaces, tetrahedral remeshing, local
crack formation, and arbitrary simulation/collision tetra meshes.
