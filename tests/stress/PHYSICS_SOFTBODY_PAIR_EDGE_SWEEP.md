# Continuous SoftBody–SoftBody edge/edge collision detection (Godot Physics 3D)

This experimental extension adds **swept structural edge-to-edge contacts**
between separate soft bodies, complementing Cgame's existing discrete
edge/edge and swept vertex/triangle XPBD contacts.

The mathematical approach is conservative advancement, comparable to the
existing Cgame Jolt backend's speculative edge sweep. No external solver
source is copied.

## Settings

Set all three under `physics/3d/solver`:

- `soft_body_pair_collision_thickness > 0`: enable inter-body contacts.
- `soft_body_pair_collision_edge_edge = true`: enable edge BVHs and
  **discrete** edge/edge contacts.
- `soft_body_pair_collision_ccd = true`: store previous positions and
  enable existing vertex/face pair CCD; required by edge history.
- `soft_body_pair_collision_edge_ccd = true`: new opt-in swept edge
  narrowphase (default **false**).

The usual compliance, max contacts per pair (256 default) and max body
pairs per step continue to apply. Enabling only the last setting is not
sufficient; all prerequisite settings above must be active.

## Mechanics

One pair of moving segments has eight endpoint positions (four previous,
four current). The maximum relative endpoint travel bounds how quickly
the minimum segment distance can shrink over the normalized physics step.
Repeatedly advance by

```
fraction += (closest_distance - thickness) / max_relative_endpoint_travel
```

with a limit of **24 iterations** and strict finite-value checks.
The current Cgame edge closest-point narrowphase handles nonparallel
segments with interior closest points. Candidate pairs are found using
each structural edge's *swept* AABB; the existing lazy edge BVH is reused.
An independent budget, at most 4,096 swept candidate checks per body pair,
prevents expensive contact work from growing indefinitely in dense scenes.

At the first entering proximity witness, freeze the two barycentric edge
parameters and initial separating normal. At frame end, enforce an
unilateral XPBD constraint along that normal, allowing correction even if
both edges have already crossed and separated. The Jacobian weights are
`(1-s, s, -(1-t), -t)`; each correction is multiplied by inverse mass,
and positions/velocities/lambda commit transactionally. Pins remain fixed.

Only enabled scenes pay the swept search cost, and it reuses the
vertex/face pair CCD previous-position vector (no second history).

## Validation

- `tests/servers/test_physics_softbody_pair_edge_sweep.cpp`:
  fast crossings, moving target and body swaps, momentum, pinned bodies,
  no-crossing, initial overlap and invalid values.
- `tests/stress/test_physics_softbody_pair_edge_sweep.py`:
  **6,000 seeded reference checks** of TOI and XPBD projection plus wiring.
- `.github/workflows/physics-softbody-pair-edge-sweep.yml`:
  focused Python regression workflow on PRs and develop pushes.

The current method is not an exact algebraic edge/edge CCD: tangential,
parallel, degenerate, grazing or endpoint contacts may be missed. Its
conservative advance limits *entering* contact only, not full temporal
mesh manifold reconstruction. Very large positional correction is
possible after deep penetration. Validate at small timesteps on real
scenes, with dynamic pins, nonuniform edge lengths, and timed CPU/RSS
benchmarks; the C++ full-engine build and scene-level collision
correctness must be confirmed independently.
