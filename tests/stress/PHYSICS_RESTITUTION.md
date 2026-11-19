# GodotPhysics: restitution combine modes

Cgame exposes `physics/2d/solver/restitution_combine_mode` and
`physics/3d/solver/restitution_combine_mode`. These options apply to the
**built-in GodotPhysics** backends, not to Jolt or third-party providers.

| Value | Rule | Example for 0.25 and 0.50 |
|---|---|---:|
| 0 | Legacy clamped sum (default) | 0.750 |
| 1 | Maximum (Box2D-style) | 0.500 |
| 2 | Average (Rapier-style) | 0.375 |
| 3 | Minimum | 0.250 |
| 4 | Multiply | 0.125 |
| 5 | Geometric mean | 0.354 |

Mode 0 intentionally preserves old project behavior. Nonlegacy modes clamp
individual coefficients to [0, 1]. Parameters are captured once when the
physical space is created; changing a ProjectSettings value does **not**
retroactively modify existing spaces.

The existing `restitution_velocity_threshold` is still applied independently:
slow impacts do not bounce, regardless of the combine mode. Material changes
on an existing body are respected at the next contact setup.

The combine rule is shared by all contacts of one rigid-body pair and mixed
**once per physics step**; there is no per-contact storage or solver-iteration
overhead. Soft-body contacts use their rigid body's bounce coefficient because
soft bodies do not expose a second restitution material parameter.

Regression coverage:
- Native: `tests/servers/test_godot_physics_restitution_combine.cpp` (build with `tests=yes`)
- Python contracts: `python3 -m unittest tests/stress/test_physics_restitution_combine.py`
- Integration: `godot --headless --path tests/stress --script res://physics_restitution_mix_regression.gd`

Physics backends should be selected to use **GodotPhysics** before starting the
integration test; an engine based on Jolt does not consume these settings.
