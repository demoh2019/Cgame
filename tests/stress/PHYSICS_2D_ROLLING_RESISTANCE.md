# GodotPhysics2D: optional circle rolling resistance

Box2D v3.1 simulates rolling resistance as a torque constraint limited by
normal load and a characteristic rolling radius. Without it, a rigid circle
rolling without slipping can keep its energy indefinitely despite ordinary
Coulomb friction.

Enable `physics/2d/solver/rolling_resistance` under Project Settings.
The default `0.0` disables this feature. Try a small positive value and
tune against your scene; this is a space-wide coefficient and affects only
built-in GodotPhysics2D (not Jolt or 3D).

The maximum angular impulse is
`resistance_coefficient * circle_radius * sum(contact_normal_impulses)`.
Only dynamic circles with angular inertia contribute; a static/kinematic
circle does not make another shape roll. With two participating circles the
smaller transformed radius is used. Non-uniformly scaled circles fall back
to existing behavior; their shape is elliptical, not circular.

A pair keeps one accumulated angular impulse and one precomputed scale
(16 bytes on real_t=double builds), not one per contact. The torque cap is
shared across solver iterations and reset at each new physics step.
When disabled, the hot solver loops skip the angular constraint.

Settings are loaded when a physics space is created, so recreate a space
after editing Project Settings to observe the new value.

Regression tests:
- C++: `tests/servers/test_godot_physics_rolling_resistance.cpp`
- Python: `python3 -m unittest tests/stress/test_physics_2d_rolling_resistance.py`
- Integration: `godot --headless --path tests/stress --script res://physics_2d_rolling_resistance_regression.gd`

This opt-in model should not be enabled by default before real engine
benchmarks, especially for large stacks with many persistent contact pairs.
