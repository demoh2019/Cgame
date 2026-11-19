# Stable anisotropic aerodynamic drag for SoftBody3D

GodotPhysics3D uses a per-triangle analytic quadratic-drag step, following
velocity-dependent force models used in cloth and soft-body simulation.

- Normal drag uses the SoftBody3D \`drag_coefficient\` and is two-sided.
- Optional tangential (skin) drag uses
  \`physics/3d/solver/soft_body_tangential_drag_ratio\` (default **0**).
- Effective coefficient for tangential drag is \`drag_coefficient * ratio\`.
- \`physics/3d/solver/soft_body_lift_coefficient\` remains independent and opt-in.
- Each face shares its mean-velocity force equally over its three vertices,
  honoring pinned vertices through their zero inverse mass.
- No persistent allocations; the additional tangential branch is skipped at
  the default setting.

For the face-averaged normal or tangential component, \`u\`, integration of
\`du/dt = -k * u * abs(u)\` gives
\`u_next = u / (1 + k * abs(u) * delta)\`.
This prevents explicit Euler overshoot and sign reversal in isolated drag.

Run the C++ unit tests with a tools test binary, for example
\`godot --headless --test --test-case="[Physics] *aerodynamic*"\`
(adapt the executable name and test filter for the local build).
Exercise high drag, high speed, pinned cloth corners and a folded mesh in
a real project; aerodynamic lift/wind and other constraints are separate
forces, so only the isolated drag component has unconditional damping.
