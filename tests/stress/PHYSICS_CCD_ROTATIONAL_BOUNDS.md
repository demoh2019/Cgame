# CCD rotational broadphase envelope (GodotPhysics2D/3D)

The legacy GodotPhysics CCD broadphase expands a shape's world AABB by
**linear displacement only**. A long, off-center collider can rotate
through an obstacle while its center barely translates, leaving the
potential collision pair absent from broadphase.

Optional Project Settings (off by default):
- `physics/2d/solver/ccd_rotational_bounds`
- `physics/3d/solver/ccd_rotational_bounds`

When CCD is enabled on a dynamic/kinematic body, its pre-solve broadphase
AABB is merged with its linearly translated AABB and then expanded by a
conservative angular displacement bound:

`2 * r * sin(min(abs(angular_displacement), PI) / 2)`

Here `r` is the farthest AABB corner from the world-space center of
mass. The angular displacement uses the physics timestep, not wall
time. The expansion is sufficient for all possible intermediate points
on a rotating shape; it also works for compound collider offsets.

The same angular sweep is used on serial and parallel force-integration
paths. The implementation introduces no new per-body/per-contact state and
only evaluates an angle/sqrt when enabled. Normal movement and ordinary
non-CCD bodies are unaffected. Expect more broadphase candidates for long
rotating colliders: that is the intended tradeoff for completeness.

**Important limitation:** This is conservative *broadphase pairing*,
not full rotational narrowphase time-of-impact. The current CCD ray or
shape casts remain primarily translation-based. Pure rotation may create
the correct potential pair without resolving an intermediate-time hit.
For complete protection against rotation-only tunneling, an angular
continuous collision solver and temporal contact constraints are still
needed.

Tests:
- Native doctests: `tests/servers/test_godot_physics_ccd_rotational_bounds.cpp`
- Python source/numerical property tests:
  `python3 -m unittest tests/stress/test_physics_ccd_rotational_bounds.py`

Both native builds and end-to-end scene benchmarks should be run before
enabling this for large numbers of objects in production.
