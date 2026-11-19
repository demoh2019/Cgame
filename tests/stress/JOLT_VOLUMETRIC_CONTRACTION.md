# Advanced Cgame physics: compressible vs incompressible XPBD soft bodies

Cgame already supports **opt-in Jolt tetrahedral volume constraints** for
closed convex soft-body surface meshes. Those constraints preserve the
original rest volume while edge springs can contract or expand via Godot's
`SoftBody3D.shrinking_factor`.

Preserving the original volume is appropriate for an approximately
**incompressible** rubber-like material: even if its outer surface wants
to shrink, the volume constraints resist compression.

For other materials, such as a contracting foam or a uniformly expanding
soft structure, the constraint system must change the *target volume*
consistently with the edge rest lengths. This PR adds that alternative
without replacing Jolt's existing XPBD solver or changing old scenes.

## New project setting

`physics/jolt_physics_3d/simulation/soft_body_volume_follow_shrinking_factor`

- **false (default):** retain the original tetrahedral rest volume while
  edge springs contract/expand; models volume-preserving soft material.
- **true:** shrink or expand the target rest volume isotropically. When
  an edge rest length has factor `s = 1 - shrinking_factor`, the target
  volume has factor `s³`. This models an elastically compressible
  material whose *rest volume* follows the imposed scale.

Both modes require
`physics/jolt_physics_3d/simulation/soft_body_volume_preservation=true`,
which enables Jolt's existing convex tetrahedral volume constraints.
When optional center-to-surface radial springs are enabled, the compressible
mode also scales their rest lengths by `s`; the incompressible mode keeps
those radial lengths at their original geometric values.
The feature applies only to new/rebuilt soft bodies; existing bodies
are not retroactively rebuilt when project settings change.

### Examples

| `shrinking_factor` | Linear rest scale | Optional volume rest scale |
| ---: | ---: | ---: |
| -0.15 | 1.15 | 1.520875 |
| 0 | 1.0 | 1.0 |
| 0.25 | 0.75 | 0.421875 |

Jolt stores **six times the signed tetrahedral rest volume** in
`SoftBodySharedSettings::Volume::mSixRestVolume`. Multiplying this
value by a positive `s³` preserves the tetrahedron's orientation.
The implementation uses double-precision intermediates and clamps
extreme results to `[-FLT_MAX, FLT_MAX]` to avoid passing infinity to
the solver. A nonfinite cubic scale is ignored. Users should keep
shrinking factors in a physically meaningful range below 1.
Nonpositive linear multipliers are ignored by the new volume mode,
leaving original volume constraints instead of inverting tetrahedra.

The volume adjustment happens only once during construction, after
`CalculateVolumeConstraintVolumes()` and before
`SoftBodySharedSettings::Optimize()`. It skips the extra loop when
the setting is disabled (default), no convex volume constraints were
generated, or there is no contraction/expansion. If optional center-to-
surface radial springs are generated, only those appended spokes are
scaled; surface springs have already been processed. No new work runs
each physics frame.

## Enable

```ini
[physics]

3d/physics_engine="Jolt Physics"
jolt_physics_3d/simulation/soft_body_volume_preservation=true
jolt_physics_3d/simulation/soft_body_volume_compliance=0.000001
jolt_physics_3d/simulation/soft_body_volume_follow_shrinking_factor=true
```

Attach a closed convex mesh to a `SoftBody3D` and set
`shrinking_factor` on the body. The volume setting can be combined
with Jolt's already integrated dihedral bending and long-range cloth
attachments. Note that Jolt's current convex fan generator intentionally
rejects concave, open or excessively complex meshes.

## Validation

```sh
python3 -m unittest tests/stress/test_jolt_volumetric_contraction.py -v
```

The independent mathematical reference checks 20,000 seeded random
signed tetrahedral rest volumes and positive/negative shrink factors,
including exact cubic scaling, orientation preservation and default-off
behavior. Source checks verify that volume scaling runs after the Jolt
volume constraints are generated but before `Optimize()`.

The headless native regression
`tests/stress/physics_jolt_softbody_volume_shrink_regression.gd`
creates three closed tetrahedral soft bodies (shrink -0.15, 0 and 0.25),
pins one vertex of each, advances 90 physics frames, records original,
target and measured volumes, and checks finite positions, bounds and
stable anchors. GitHub Actions runs this fixture **four times**,
with volume-follow mode `false`/`true` crossed with optional radial
springs `false`/`true`, and archives separate logs.

The native test is a smoke/regression check, not a precision validation
of FEM materials or a guarantee that the solver reaches its exact target
volume in 90 frames. Compare actual volume errors and CPU/RAM before
claiming performance or numerical accuracy improvements.

## Upstream references

- [Jolt SoftBodySharedSettings::Volume](https://jrouwe.github.io/JoltPhysics/struct_soft_body_shared_settings_1_1_volume.html)
- [Godot SoftBody3D shrinking_factor](https://docs.godotengine.org/en/stable/classes/class_softbody3d.html)
