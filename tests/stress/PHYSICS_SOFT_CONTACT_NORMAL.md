# 3D rigid / soft-body contact normal hardening

GodotPhysics3D expects unit-length normals in effective mass, friction,
and bias impulse math. A zero normal from degenerate narrowphase geometry
could otherwise disable all separating impulses. A non-unit normal could
amplify or attenuate the solver response.

`godot_physics_3d_soft_contact_normal()` preserves the existing
narrowphase-based orientation for the usual unit-vector case and does
not use a square root there. When the narrowphase normal is non-unit,
it normalizes it. If it is zero or invalid, it falls back to the
point-separation axis; when both are degenerate, it returns the
deterministic +Y axis.

Only the GodotPhysics3D rigid/soft contact callback is changed; existing
rigid/rigid behavior and Jolt remain untouched. No contact memory is added.

Regression coverage:
- `tests/servers/test_godot_physics_3d_contact_normal.cpp` (native doctest)
- `python3 -m unittest tests/stress/test_physics_contact_geometry_regressions.py`

This prevents invalid normals at contact creation but is not a substitute
for mesh quality validation or full soft-body stability regression.
