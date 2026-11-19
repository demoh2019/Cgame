# Advanced Jolt Physics: anisotropic woven-cloth spring compliance

Real woven cloth has different mechanical response along its fiber
direction and perpendicular to it. Ordinary isotropic XPBD spring
constraints apply the same `compliance` irrespective of the direction
of each spring. Jolt stores compliance separately for every edge
(`SoftBodySharedSettings::Edge::mCompliance`), allowing direction-dependent
material stiffness **without implementing another solver**.

Cgame now supports an opt-in directional cloth material applied during
`SoftBody3D` construction, before constraint optimization.

## New project settings

| Setting | Default | Meaning |
| --- | ---: | --- |
| `physics/jolt_physics_3d/simulation/soft_body_fiber_axis` | `0` | Local mesh axis: 0 = X, 1 = Y, 2 = Z |
| `physics/jolt_physics_3d/simulation/soft_body_fiber_compliance_multiplier` | `1.0` | 0.1–10 multiplier for edges aligned with the selected axis |

A multiplier below 1 makes springs along the selected local axis
**stiffer**; above 1 makes them **more compliant**. Edges perpendicular
to that axis retain their original compliance. Edges between the two
directions receive a smooth intermediate stiffness.

Let `d` be the vector between the edge's vertices **in the rest pose**,
`a` the selected unit fiber axis, `m` the configured multiplier and
`C` the edge's original XPBD compliance:

```
alignment² = dot(normalize(d), a)²
C_directional = C * (1 + (m - 1) * alignment²)
```

For `m=4`, X-aligned springs have four times the original compliance;
Y- or Z-aligned springs are unchanged; diagonal XY springs have 2.5x
compliance. The material direction rotates with the soft body's local
mesh frame rather than changing with its world-space rotation.

## Safety and compatibility

- **Default 1.0 is fully isotropic**. The entire additional per-edge
  processing loop is skipped, preserving previous simulation semantics,
  CPU and memory behavior.
- The new pass runs **once when creating/rebuilding** soft-body
  constraints. It never adds work to the physics frame or allocations.
- Jolt's `FLT_MAX` sentinel for disabled edge springs and exact zero
  for rigid springs are both preserved.
- Very short/invalid rest-pose edges and nonfinite compliance or
  geometry are ignored. Intermediate arithmetic is double precision;
  the final compliance is bounded by `FLT_MAX`.
- It processes only surface springs produced by
  `SoftBodySharedSettings::CreateConstraints()`, **before** Cgame's
  optional center-to-surface radial volume springs are created. Thus
  independent volume and radial stiffness parameters are unaffected.
- Other already implemented physics remain available: LRA tethers,
  dihedral bending, aerodynamic drag and convex tetrahedral
  preservation. Individual `SoftBody3D` nodes still share the global
  anisotropy setting at creation; per-material/per-node fiber vectors
  and full orthotropic constitutive tensors are **future work**.

## Activate

```ini
[physics]

3d/physics_engine="Jolt Physics"
jolt_physics_3d/simulation/soft_body_fiber_axis=0
jolt_physics_3d/simulation/soft_body_fiber_compliance_multiplier=0.25
```

Use an indexed cloth mesh whose material weave is aligned with local X.
The setting applies to newly constructed soft bodies, not existing
soft-body instances without rebuild.

## Regression validation

```sh
python3 -m unittest tests/stress/test_jolt_softbody_anisotropic_fiber.py -v
```

The Python reference checks random edge orientation and compliance
scaling in **20,000 seeded samples**, special X/Y/Z/diagonal cases,
default-off equivalence, invalid edges and Jolt sentinel preservation.
Source contracts verify no changes to later volumetric radial springs.

The native headless GDScript
`physics_jolt_softbody_anisotropic_fiber_regression.gd` constructs two
12×12 pinned fabric grids, applies orthogonal X/Y vertex impulses,
advances 36 frames and checks pinned anchors, finite positions/bounds,
and numerical stability. CI runs five explicit configurations:

- X axis × multiplier 1.0 (isotropic baseline)
- X axis × 0.25 (stiffer X fibers)
- X axis × 4.0 (softer X fibers)
- Y axis × 4.0 (softer Y fibers)
- Z axis × 4.0 (out-of-plane fiber control)

The fixture records X/Y displacement to support comparative CPU,
stability and material testing. The numerical/reference checks are not
a replacement for a native Jolt build or solver validation. Actual FPS,
memory and deformation accuracy must be measured in controlled
before/after engine runs.

## Sources

- [Jolt SoftBodySharedSettings::Edge](https://jrouwe.github.io/JoltPhysicsDocs/5.7.0/struct_soft_body_shared_settings_1_1_edge.html)
- [XPBD / physically-based anisotropic cloth modeling](https://onlinelibrary.wiley.com/doi/10.1111/cgf.15248)
