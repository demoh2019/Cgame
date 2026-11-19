# GodotPhysics 2D/3D: PhysX-style static versus dynamic friction

**New space-wide Project Settings**:

- `physics/2d/solver/static_friction_multiplier`
- `physics/3d/solver/static_friction_multiplier`

Default `1.0` keeps the original Coulomb friction behavior: the same
coefficient bounds both resting and sliding contacts. To increase traction
on slopes and stop low-speed sliding, try `1.5` or `2.0`.

A physical material's existing friction coefficient (combined according
to the project's `friction_combine_mode`) is interpreted as **dynamic**
friction. Its static coefficient is
`static_friction_multiplier * dynamic_friction`.

For each contact, the unconstrained accumulated tangent impulse is tested
against the static cone. If it fits, the impulse is kept (sticking).
Otherwise, it is projected onto the smaller dynamic friction cone
(sliding). Warm-started impulses are capped by the static cone, including
after materials change. In 3D, the cone uses the **vector magnitude**,
not per-axis clamping. The native implementation avoids square roots for
contacts which remain within the static cone.

Works for the GodotPhysics 2D rigid/rigid, 3D rigid/rigid, and 3D
rigid/soft-body solvers. It does not change third-party physics backends.
No new per-body/contact state is added; each space caches one scalar
setting. The default is backwards-compatible, and on the default branch
the original dynamic friction solver projection remains unchanged.

The property is captured on physics-space creation, so changes to
ProjectSettings require a new physics space.

## Verification

- C++ numerical doctest:
  `tests/servers/test_godot_physics_contact_static_friction.cpp`
- Python source and formula contracts:
  `python3 -m unittest tests/stress/test_physics_static_friction.py`

Build and benchmark the native engine before enabling this option as a
project-wide default. With a larger static cone, individual contacts
can remain stuck for longer and may exhibit more noticeable transitions
when the static cone is exceeded.
