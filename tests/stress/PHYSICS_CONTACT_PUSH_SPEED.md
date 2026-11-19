# GodotPhysics: limit excessive contact separation speed

Use these Project Settings for the **GodotPhysics** backend:

- `physics/2d/solver/max_contact_push_speed` (pixels/second)
- `physics/3d/solver/max_contact_push_speed` (meters/second)

The default is `0.0` (**unlimited**) for backwards compatibility.
Choose a positive value to limit penetration recovery speed when rigid bodies
or rigid/soft contacts are deeply interpenetrating. For example, a configured
limit of `2.5` in 3D ensures the scalar contact separation velocity bias
does not exceed 2.5 m/s.

The cap modifies **penetration-correction bias only**. It does not clamp body
linear velocity, change physical restitution, or enforce CCD. Contact custom
bias is still respected prior to capping. A lower limit may make bodies take
multiple physics steps to separate from deep overlaps.

This is read once when a physics space is created, matching the existing
friction and restitution tuning settings, and it adds no per-contact memory
or solver-iteration cost. Jolt and external physics backends do not consume it.

Tests:
- Native `tests/servers/test_godot_physics_contact_push_speed.cpp` with `tests=yes`.
- `python3 -m unittest tests/stress/test_physics_contact_push_speed.py`

Reference: Box2D world contact tuning `pushSpeed` and PhysX
`maxDepenetrationVelocity`.
