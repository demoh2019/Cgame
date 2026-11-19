# Jolt SoftBody3D: finite XPBD parameters and validated mesh topology

Godot exposes a soft-body linear stiffness coefficient in **[0, 1]** and a
simulation precision parameter. Jolt converts Godot's stiffness to inverse
stiffness (XPBD compliance), which is used when creating the soft-body
edge constraints.

The previous Jolt adapter allowed zero simulation precision (the setter
clamped to 0), then divided by this value when constructing the shared
settings. Setting stiffness to zero also computed `1.0 / 0.0` and passed an
infinite compliance to Jolt.

Jolt's `SoftBodySharedSettings::VertexAttributes` explicitly documents
**`FLT_MAX`** as the sentinel that disables spring edges. The new code:

- Clamps simulation precision to **at least one iteration**, before
  comparing it with the existing setting. Godot's normal precision values
  of 1 and higher keep the same meaning.
- Maps zero stiffness to `FLT_MAX`, not infinity. Positive stiffness
  follows the original XPBD conversion, computed in double precision and
  saturated at `FLT_MAX` to avoid intermediate float overflow. Stiffness
  1 still maps to zero compliance.
- Refuses NaN/infinite mass and stiffness parameter values. The original
  checks for non-positive mass and coefficient clamping remain in place.
- Validates that an indexed soft-body mesh has **whole triangles** (index
  count divisible by 3) and that every index lies within the vertex
  buffer, **before allocating Jolt constraint settings**. This prevents
  invalid geometry from indexing past the end of either array.
- Retains the existing mesh welding, face winding, Jolt constraint
  optimization and physics solver, including the earlier compact vertex
  index cache.

These changes follow defensive input validation used in physics engines:
reject malformed geometry before building acceleration/constraint data, and
keep numerical parameters finite at the API boundary.

## Tests

```sh
python3 -m unittest tests/stress/test_jolt_softbody_constraint_bounds.py -v
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --path tests/stress \
  --script res://physics_jolt_softbody_constraint_bounds_regression.gd
```

The numerical model exercises **10,000 deterministic combinations** of
stiffness, mass, precision and vertex count, including stiffness zero,
extremely small positive stiffness and negative precision. The source
contract checks that malformed mesh indices are rejected before allocating
physics settings.

The native Jolt regression creates five tetrahedral soft bodies with
stiffness 0, 0.000001, 0.5 and 1.0, with precision values 0, -3, 1, 3
and 7. It advances five physics frames and checks finite vertex positions,
finite bounds and precision clamping. CI explicitly selects `Jolt Physics`
and archives the log.

The **native test must pass before considering this implementation fully
validated**. This is a correctness/stability fix rather than a measured FPS
optimization; it prevents invalid solver inputs and crashes from malformed
mesh topology.

## Upstream references

- Jolt `SoftBodySharedSettings::VertexAttributes`: documents `FLT_MAX`
  to disable spring constraints.
- Godot `PhysicsServer3D.soft_body_set_linear_stiffness`: accepts [0, 1].
- Jolt soft-body constraint construction: `CreateConstraints`, then
  `Optimize`.

This change does **not** resolve the separate TODO about retrieving
render meshes from `RenderingServer` on a separate physics thread.
That deadlock risk requires staging mesh arrays with explicit thread
and resource-lifetime ownership.
