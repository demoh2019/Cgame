# Advanced Jolt soft-body physics: LRA-compatible cloth shrink/expand

Jolt's optional **Long-Range Attachments (LRA)** add tethers from pinned
vertices to other vertices, limiting excessive cloth stretch. Cgame also
supports Godot's `SoftBody3D.shrinking_factor`, which scales the **rest
lengths of all ordinary cloth edge springs** at body construction.

Before this change, enabling both features shortened or expanded the
edge springs but left each tether's maximum distance at the original
rest-pose size. A shrunken cloth would still allow a far vertex to
stretch to its old anchor distance, defeating part of the contraction.

## New behavior

The Jolt adapter now applies the *same rest-length multiplier* to
both ordinary edge constraints and long-range attachment limits:

```
multiplier = 1 - shrinking_factor
edge.mRestLength *= multiplier
lra.mMaxDistance *= multiplier
```

This is done after Jolt `CreateConstraints()` has calculated its
Euclidean/geodesic anchor distances, and before the
`SoftBodySharedSettings::Optimize()` pass reorders constraints for
parallel solution.

- **Positive shrink** (`0.25`): an initial tether limit of 2 meters
  becomes 1.5 meters.
- **No shrink** (`0`): unchanged. The extra LRA pass is skipped.
- **Negative shrink** (`-0.15`): allows 15% expansion; an original
  2-meter tether becomes 2.3 meters.

Godot documents negative `shrinking_factor` values as expansion, so
this change does **not** clamp negatives away. The legacy unmodified
spring behavior remains intact when LRA is disabled.

There is no new per-frame solver loop. Additional work is **one pass
over generated tethers on soft-body creation only when both LRA and
a nonzero shrinking factor are enabled**. Other objects are unaffected.

## Tests

```sh
python3 -m unittest tests/stress/test_jolt_softbody_lra_shrink.py -v
```

The source contracts verify the exact same multiplier is used, that LRA
is generated after valid pinned points and scaled **before**
`Optimize()`, and that the zero-shrink fast path has no extra iteration.
The independent numerical reference tests 20,000 seeded random
edge/tether lengths and positive/negative shrink factors.

A native Jolt physics fixture,
`tests/stress/physics_jolt_softbody_lra_shrink_regression.gd`,
constructs three 12×12 hanging cloth objects with top-row pinned
vertices, applies shrink values `-0.15`, `0` and `0.25`, advances
90 physics steps and verifies finite coordinates, stable pins and a
conservative upper bound on anchor distances.

CI runs the fixture **twice**: once with Euclidean LRA, once with
geodesic LRA, inserting the relevant physics settings into the
existing `project.godot` section. It archives separate logs and
requires the pass marker.

Native C++ builds and physical simulation must pass before this can be
considered verified. This is primarily a **physics consistency**
enhancement. A frame-rate or RAM improvement is not claimed; optional
LRA can increase the number of physics constraints.

## Reference

- [Jolt SoftBodySharedSettings: LRA / constraint settings](https://jrouwe.github.io/JoltPhysicsDocs/5.7.0/class_soft_body_shared_settings.html)
- [Godot SoftBody3D: shrinking_factor](https://docs.godotengine.org/en/stable/classes/class_softbody3d.html)
