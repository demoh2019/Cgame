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

## Optional occupancy exclusion contexts

`exclusion_positions` supplies up to 128 **known** finite world-space positions;
`min_exclusion_distance` rejects candidates closer than that radius to
**any** such point. A zero radius disables the filter. The boundary is
inclusive, and `horizontal_only` also controls exclusion distance.
The same exclusion test runs in `query()`, `query_positions()`,
`query_top_positions()`, and `query_spread_positions()`; it is performed
before weighted threat scoring, with worst-case O(N * 128) checks for N
candidates. Invalid arrays or nonfinite/negative radii leave prior settings
unchanged.

```gdscript
query.exclusion_positions = PackedVector3Array([other_enemy.global_position])
query.min_exclusion_distance = 3.5
var spawn_points := query.query_spread_positions(2, 5.0)
```

This is an explicit geometric filter, **not** automatic physics overlap
detection, line of sight, or navigation validation. Albion After's authoritative
raid reinforcements supply living infected positions and preserve deterministic
stock-Godot fallback when more than 128 contexts are present.

## Per-candidate tactical score bonuses

`candidate_bonuses` is an optional `PackedFloat32Array` aligned by source
index with `candidates`. Each finite element must be between -1 and +1;
negative values penalize a point, positive values prioritize it. The engine
adds the offset to the existing distance/threat score **after** applying
exclusions and clearance constraints. An empty array means no bonus, so old
queries remain unchanged. A candidate list with a different length clears
existing offsets; malformed updates leave the previous values intact.
`query()`, `query_top_positions()`, and `query_spread_positions()` share
identical ranking and deterministic tie breaking.

Albion After feeds small, server-calculated cover-proximity bonuses into its
raid reinforcement EQS to favor positions near physical obstacles while still
rejecting obstructed terrain, safe zones, player clearance violations and
occupied sites. This is a proximity heuristic, not verified line of sight:
obstacle visibility/navmesh reachability remain gameplay responsibilities.
Stock Godot and older Cgame builds use the matching GDScript fallback.
