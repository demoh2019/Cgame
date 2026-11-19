# Stribeck-like velocity-dependent Coulomb friction (GodotPhysics3D)

Contact friction can now transition smoothly from the static coefficient
to the kinetic coefficient as two surfaces begin to slide.

## Configuration

- \`physics/3d/solver/static_friction_multiplier = 2.0\` — ratio between
  static and dynamic friction. Default is **1.0** (legacy).
- \`physics/3d/solver/stribeck_transition_velocity = 0.25\` — velocity
  scale (m/s). Default is **0**, keeping the existing two-cone solver.

Effective friction at tangential slip speed \`v\`:

\`mu(v) = mu_dynamic * [1 + (static_multiplier - 1) / (1 + (v / transition_velocity)^2)]\`.

At zero slip: \`mu_static\`. At one transition speed: halfway.
At high slip: \`mu_dynamic\`. This is an efficient rational **Stribeck-like**
approximation, NOT the exponential LuGre constitutive law and not a
stateful friction model. It cannot reproduce presliding hysteresis.

- Applies to rigid-rigid and rigid-soft-body contacts in GodotPhysics3D.
- The existing cached normal impulse limits the friction impulse;
  warm starts remain bounded by the static cone.
- The new speed-dependent solver uses ONE effective friction cone.
  Applying the old static cone again would double-count stiction.
- Feature is disabled by default; disabled path preserves legacy math.
- Zero per-contact memory. Each active slip incurs ~1 rational evaluation
  (only when both knobs enable the feature).
- Impulse sign remains opposed to slip (dissipative velocity correction).
- This does NOT change JoltPhysics, which has its own contact solver.

## Tests

\`python3 -m unittest discover -s tests/stress -p test_physics_stribeck_friction.py -v\`

C++ doctest: \`tests/servers/test_godot_physics_stribeck_friction.cpp\`.

Next: compare measured sliding thresholds against physical reference
materials, add timestep/substep rate sweeps and profile the solver.
