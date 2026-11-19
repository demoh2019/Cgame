# Cgame Joint3D progressive structural fatigue

Opt-in accumulated-damage fracture for **rigid-body joints** in the
built-in GodotPhysics3D backend.

Existing Cgame breaking reacts to a SINGLE reaction-force / torque
threshold. This extends it so a repeatedly loaded structure can fail
after **sustained subcritical stress**, before either instant-break limit
is exceeded. Useful for bridges, suspension joints, robotics, vehicles,
moving machinery, and destructible structures.

Inspired by the constraint break-force mechanisms described by PhysX
and Jolt. The *fatigue damage* formulation is a simple deterministic
engineering approximation, **not a rainflow cycle-counted S–N model**.

## Joint3D inspector settings

- \`break_force = 100.0\` (newtons)
- \`break_torque = 0.0\` (N·m; 0 ignores torque)
- \`fatigue_rate = 10.0\` (damage coefficient per second, **0 = OFF**)
- \`fatigue_yield_ratio = 0.5\` (fraction of the break limit; 0..0.99)

The existing \`broken\` signal is emitted after either instantaneous or
fatigue failure. New \`get_fatigue_damage()\` returns accumulated D in
[0,1] for live health bars, debugging and instrument panels. It can also
be queried through \`PhysicsServer3D.joint_get_fatigue_damage(RID)\`.

You must set at least one nonzero break limit; a zero limit means that
reaction channel is ignored, not division by zero.

## Numerical model

At the END of a simulation tick, the solver has already collected
joint reaction force F and torque τ. Let

\`u = hypot(|F|/break_force, |τ|/break_torque)\`

for nonzero break thresholds, with missing channels zero.

\`D_next = min(1, D_old + fatigue_rate * dt * max(0,u-yield_ratio)^2)\`.

Break at \`D>=1\`; old instantaneous break thresholds still take
priority. There is **no healing**. At constant loading, integrating
damage is independent of fixed-step subdivision. Inactive/sleeping
joints cannot accumulate the same cached reaction twice: each source
reaction solver-island timestamp is consumed once.

This uses the existing breakable-joint set and break queue; break
callbacks remain outside the multi-threaded solver via query flushing.
Reconfiguring/replacing a joint starts with new damage=0 and preserves
its user-set fatigue rate/yield. Does not allocate per-step joint state.

## Limits

- GodotPhysics3D only. Other backends keep their inherited no-op
  PhysicsServer3D fatigue methods.
- One combined normalized force/torque envelope; no load reversal
  tracking, mean-stress correction, thermal fatigue, or brittle crack
  geometry.
- Reaction is sampled after the last substep in a tick; high-frequency
  transient peaks within substeps require additional sampling.
- Fully pinned/static-only joints with zero measurable reaction do not
  accumulate fatigue.
- No physical fragmentation of rigid meshes: joints detach and
  collision exclusions are removed, existing objects remain intact.

## Tests

C++ doctest: \`tests/servers/test_physics_joint_fatigue.cpp\`.

Standalone compiled material helper:
\`g++ -std=c++17 -O2 -Wall -Wextra -Werror -I. tests/stress/test_physics_joint_fatigue_compiler.cpp -o /tmp/joint_fatigue && /tmp/joint_fatigue\`

Python stress:
\`python3 -m unittest discover -s tests/stress -p test_physics_joint_fatigue.py -v\`.

Next: fatigue per measured constraint impulse per substep, spring
relaxation/damage-induced stiffness degradation, true crack propagation,
S–N curves and stress-cycle counting.
