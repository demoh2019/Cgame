# Advanced Jolt cloth physics: XPBD Long-Range Attachments (tethers)

## New feature

Cgame's Jolt backend now optionally creates **long-range attachment
constraints (LRA)** when constructing a soft body with pinned points.
Tethers limit the distance of free cloth vertices from nearby fixed
vertices, helping prevent visibly excessive stretch under gravity,
external forces and low solver-iteration budgets.

Jolt already supplies native LRA generation and constraint solving.
Cgame now makes these available through project settings rather than
implementing another solver or adding per-vertex work to every frame.

| Project setting | Default | Values |
| --- | --- | --- |
| `physics/jolt_physics_3d/simulation/soft_body_lra_mode` | `0` | `0` Disabled, `1` Euclidean, `2` Geodesic |
| `physics/jolt_physics_3d/simulation/soft_body_lra_max_distance_multiplier` | `1.0` | At least `1.0`, e.g. `1.05` for 5% slack |

**Euclidean** LRA uses the straight-line distance from a vertex to the
nearest pinned point in the rest mesh. **Geodesic** LRA measures distance
along triangle-mesh edges; it can accommodate folds and irregular cloth
topology without treating shortcuts through space as edge paths.

If no vertices are pinned, the adapter leaves LRA disabled even when the
project mode is enabled, avoiding Jolt's nearest-kinematic search.

## Semantics and performance

- The default mode `Disabled` preserves the behavior and runtime costs of
  existing projects; modes are explicitly opt-in.
- Tether generation occurs during `SoftBodySharedSettings::CreateConstraints`
  **after** Cgame marks pinned vertices with zero inverse mass and **before**
  Jolt reorders constraints for parallel solving with `Optimize()`.
- LRA settings are global and are **snapshotted when constructing/rebuilding
  a soft body**. Existing bodies are not retroactively regenerated.
- Modes `Euclidean` and `Geodesic` require additional constraints and
  can increase CPU and memory consumption. Geodesic also performs more
  graph-related work during creation; use it when mesh topology matters.
- The multiplier is clamped to at least 1, and NaN/infinity is replaced by
  1.0, so settings never create negative or nonfinite tether lengths.
- This feature can be used together with the already available optional
  XPBD `Distance`/`Dihedral` bending and quadratic aerodynamic drag.

## Try it

Set the following in Project Settings and restart/run a scene containing
a Jolt `SoftBody3D` with a pinned edge:

```ini
[physics]

3d/physics_engine="Jolt Physics"
jolt_physics_3d/simulation/soft_body_lra_mode=2
jolt_physics_3d/simulation/soft_body_lra_max_distance_multiplier=1.05
```

The Jolt-specific keys appear under Physics → Jolt Physics 3D →
Simulation. To compare results and performance, test the same mesh,
fixed points, forces and physics tick rate using modes 0, 1 and 2.

## Regression tests

```sh
python3 -m unittest tests/stress/test_jolt_softbody_long_range_attachments.py -v
```

For native Cgame CI, the `whole-engine-stress.yml` workflow builds the
Jolt backend and runs
`physics_jolt_softbody_lra_regression.gd` **three times**, explicitly
selecting one of Disabled, Euclidean and Geodesic for each run in
`project.godot`. The fixture constructs a 12x12 cloth grid, pins its top
edge before insertion, simulates 90 frames and checks finite positions,
pinned-point stability and a conservative distance bound when tethers
are enabled.

The independent Python model uses Dijkstra's shortest-path algorithm on
256 randomly shaped connected cloth grids, checking the fundamental
property that geodesic distances are at least the Euclidean distance.
It also verifies Jolt's LRA generator uses nearest pinned points and
that the Cgame adapter configures constraints before Jolt `Optimize()`.

This adds functionality rather than promising a universal FPS boost.
Track per-scene physics tick cost, soft-body constraint count and RSS
before choosing the more expensive modes.

## Sources

- Jolt Physics `SoftBodySharedSettings::ELRAType` and
  `VertexAttributes::mLRAMaxDistanceMultiplier`:
  https://jrouwe.github.io/JoltPhysicsDocs/5.7.0/class_soft_body_shared_settings.html
- Original long-range attachments method:
  Tae-Yong Kim, Nuttapong Chentanez and Matthias Müller-Fischer,
  *Long Range Attachments — A Method to Simulate Inextensible Clothing
  in Computer Games*.
