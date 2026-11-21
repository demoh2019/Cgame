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
reachability/path cost, smart objects, dynamic area masks, async
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

## Bounded native top-K for large infected packs

`query_top_positions(count)` chooses the best 1–64 candidate positions in
O(N*K) time and O(K) memory with a stable source-index tiebreaker, sharing
all filtering and scoring with `query()`. No per-candidate Dictionary and
no full sort; `max_results` remains respected. Albion After now reuses one
query Resource per infected and replans a flank only every 0.30 seconds or
when either target moves over 1m or infected over 1.8m. Same best-three
flank distribution; direct chase remains for bosses, brutes and stock Godot.

Tests: `tests/scene/test_environment_query_3d.cpp`, numerical Python
contracts `tests/scene/test_environment_query_topk.py`, and live zombie AI
checks. Engine binary and server benchmark still required for measured gains.

## Separated multi-position selection

`query_spread_positions(count, min_separation)` performs a deterministic
score-first, distance-separated selection for up to 64 positions. Unlike
`query_top_positions(count)` followed by filtering nearby results, it
continues scanning other eligible candidates when a highly ranked point is
too close to an already chosen point. Equal scores use original candidate
indices. `horizontal_only` also applies to pairwise spacing. `max_results`
caps the number returned, not the set of eligible candidates evaluated.
Invalid counts/separation return an empty result.

The raid reinforcements system in `game/scripts/shared/raid_reinforcements.gd`
uses this native API on Cgame binaries. It only sends server-vetted positions
after terrain, water, player distance and occupancy checks. Stock Godot and
older Cgame binaries continue to use an equivalent stable GDScript algorithm.
The native query does not replace the server's trust boundary.

## Occupied-position exclusion for safe group goals

The new `query_spread_positions_avoiding(count, min_separation, occupied_positions, clearance)`
method excludes candidate points closer than `clearance` to any occupied
position **before ranking and spacing**. The occupied array is capped at 128
finite positions and the clearance must be finite and nonnegative. An exact
clearance-boundary match is allowed; zero clearance disables exclusions.

This is a pure mathematical, deterministic CPU filter, **not a physics or
navigation occupancy test**. Set `horizontal_only = true` to check XZ-plane
distances as needed for 3D actors on uneven terrain.

Albion After's server-owned raid reinforcement planner now snapshots alive
infected coordinates per wave and uses this native operation for collision-free
spawn selections. Both ordinary Godot and older Cgame binaries use a
deterministic GDScript fallback, including for more than 128 occupied positions.
All terrain, player-safety, danger-zone and group-spacing constraints remain
authoritative. Neither network messages nor saves are changed.

Test coverage: C++ unit cases in `tests/scene/test_environment_query_3d.cpp`,
game `game/tests/test_raid_reinforcements.gd`, and Python source-contract and
numerical model checks in `tests/scene/test_environment_query_occupancy.py`.

The native C++ build and headless Godot tests must pass before production
performance claims; this source change alone is not a measured speedup.
