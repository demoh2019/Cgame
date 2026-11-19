# Environment Query 3D — runtime MVP (roadmap item #35)

This is a lightweight, native **spatial query** for game AI. It ranks candidate
world positions without allocating nodes, mutating the game scene, or accessing
PhysicsServer/NavigationServer. Each query is deterministic and can be
serialized as a `Resource`; a query resource can be reused sequentially by multiple AI controllers,
but callers must not mutate shared query properties concurrently.

## Example (GDScript)

```gdscript
var query := EnvironmentQuery3D.new()
query.origin = global_position
query.candidates = EnvironmentQuery3D.sample_ring(global_position, 12.0, 24)
query.horizontal_only = true

query.use_threat = true
query.threat_position = target.global_position
query.min_threat_distance = 5.0
query.desired_distance = 8.0
query.distance_weight = 1.0
query.safety_weight = 0.5
query.max_results = 5

var ranked: Array = query.query()
if not ranked.is_empty():
    var next_destination: Vector3 = ranked[0]["position"]
    # Use NavigationAgent3D to validate navigation and move toward it.
```

`query()` returns dictionaries containing `position`, `index`,
`score`, `distance`, and `threat_distance`. The score is
`distance_weight * (1 - min(1, abs(distance - desired_distance) / max(max_distance, 1)))`
plus, when enabled, `safety_weight * min(1, threat_distance / max(max_distance, 1))`.
Results are sorted by descending score, with source index breaking ties.

`sample_grid(center, half_extents, spacing, max_points)` generates an XZ
lattice and rejects accidentally excessive allocation. A ring accepts
1..4096 points; a grid is limited to a maximum of 65536 points.

## Scope and limitations

This is a **foundation**, not the full EQS implementation seen in Unreal.
It does not yet implement obstacle raycasts, ground projection, navmesh
reachability/path cost, smart objects, occupancy checks, area masks, async
execution or a visual query editor. Those belong to separate incremental PRs.
Sampling is deterministic and CPU-side; large candidates arrays may be
expensive because all results are scored and sorted.

## Tests

The native C++ regression suite includes 35 `TEST_CASE`s covering distance
filters and exact boundaries, preferred distance, stable ties, threat scoring
and safety exclusions, horizontal distance, invalid input, result capping,
cardinal/grid sampling, determinism, allocation guards and Resource
serialization.

Build and run when a Godot build machine is available:

```sh
scons platform=linuxbsd target=editor dev_build=yes tests=yes module_environment_query_enabled=yes
bin/godot.linuxbsd.editor.dev.x86_64 --headless --test --test-case="*[EnvironmentQuery3D]*"
```

Do not merge without a real C++ build, tests and review.
