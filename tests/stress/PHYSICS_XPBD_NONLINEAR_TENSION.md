# XPBD nonlinear tensile hardening — GodotPhysics3D

Opt-in phenomenological nonlinear elastic response for surface/rope links.
Unlike FEM volumetric soft bodies, this model changes compliance of the
existing XPBD spring links and does not simulate volumetric stress.

Project settings:

- \`physics/3d/solver/soft_body_xpbd_compliance\` must be positive to
  activate the XPBD link solver.
- \`physics/3d/solver/soft_body_xpbd_tension_hardening\` (default 0):
  quadratic tensile stiffening strength.
- \`physics/3d/solver/soft_body_xpbd_tension_yield_strain\` (default 0.1):
  relative stretch beyond which nonlinear stiffening activates.

At each timestep, predicted length \`L\` and (possibly plastically changed)
rest length \`L0\` set the link's effective compliance:
\`excess = max(0, L/L0 - 1 - yield)\`,
\`alpha_eff = alpha / (1 + min(1e6, strength * excess^2))\`.

Each effective compliance is frozen before XPBD iterations. Updating it
while maintaining the per-link accumulated multiplier causes numerical
oscillation. Hardening never changes compression response or pins.

When hardening is off, the extra compliance buffer is freed and no extra
geometry pass runs. When enabled: O(links) time once per physics step
and O(links) real_t scratch memory. Jolt is unaffected.

Python contracts:
\`python3 -m unittest discover -s tests/stress -p 'test_physics_xpbd_tension_hardening.py' -v\`

Additional C++ doctest cases:
\`tests/servers/test_physics_xpbd_tension_hardening.cpp\`.

Further work: tetrahedral FEM, fracture/damage, and continuum hyperelastic
constitutive models.
