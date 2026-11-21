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

## UE-style directional dot test for AI position queries

An optional directional filter allows the same query to select forward, side,
or rear candidates without scene nodes or physics raycasts. This follows the
context + directional Test concept in Unreal EQS while remaining a small,
deterministic geometric primitive. It is opt-in, shared by `query()`,
`query_positions()`, `query_top_positions()` and
`query_spread_positions()`, and runs before heavier threat scoring.

```gdscript
query.use_direction = true
query.direction_origin = player.global_position
query.direction_axis = (player.global_position - enemy.global_position).normalized()
query.min_direction_dot = -0.25 # sides and far side; excludes direct near side
query.horizontal_only = true
```

The direction origin is independent of the travel origin, the cosine cutoff is
inclusive and finite in [-1, 1], and zero-length candidate directions are
rejected when enabled. In XZ-only mode, a vertical-only axis rejects all
candidates rather than relying on an undefined direction. Invalid axis,
origin and cutoff setters preserve the previous values. Leaving
`use_direction` disabled retains the existing query ordering and output.

Albion After infected use the directional filter when the native feature
exists; older Cgame binaries retain legacy ring ranking, and stock Godot
continues directly pursuing targets. This geometry-only feature never
overrides validated targeting, safe-zone, melee or navigation rules.

Reference: https://dev.epicgames.com/documentation/en-us/unreal-engine/eqs-node-reference-tests-in-unreal-engine

## Terrain-height difference test (EQS-style prefilter)

The optional native `max_vertical_difference` filter rejects candidate points
whose world-space Y differs from the query `origin.y` by more than the given
threshold. An exact-boundary candidate is allowed; zero disables the test.
It runs before threat scoring for `query()`, `query_positions()`, top-K and spread,
and works even when `horizontal_only=true`. It does not sample terrain or
prove navigation reachability: callers supply server-vetted candidate heights.

Albion After's raid reinforcement planner passes authoritative terrain heights
and the boss's elevation to the native query, rejecting high shelves and deep
valleys before selecting spread spawn sites. Older Cgame/stock Godot uses an
identical script fallback. An invalid or truncated height context fails closed.

This is a small geometric analogue of Unreal EQS distance/height tests; navmesh
path cost and line-of-sight tracing are independent future systems.
Reference: https://dev.epicgames.com/documentation/en-us/unreal-engine/eqs-node-reference-tests-in-unreal-engine

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

## Stable top-K candidate identities (Unreal EQS-style item handles)

`EnvironmentQuery3D.query_top_indices(count)` returns a
`PackedInt32Array` of the original candidate **indices**, sorted by the same
deterministic score (descending), with original-index tie breaking as
`query_top_positions(count)`. Both use the identical distance, threat,
direction, clearance, and terrain-height tests. The integer result avoids
allocating metadata dictionaries or copying candidate coordinates, and
preserves two distinct candidate slots even if their positions coincide.
Counts must be in 1..64, and `max_results` still applies. Invalid requests
return an empty packed array.

```gdscript
var indices: PackedInt32Array = eqs.query_top_indices(8)
for index in indices:
    var location: Vector3 = eqs.candidates[index]
    # Stable index identifies the associated Smart Object slot.
```

Albion After's actual zombie flanking logic now consumes source indices
directly when constructing authoritative per-target Smart Object slot IDs.
Previously it reidentified each ranked point with a nested floating-point
distance comparison to the eight ring positions. The new engine feature
removes this fragile O(K²) coordinate matching and retains the exact
ranked order and lease rules. Older Cgame builds use the previous position
query, while stock Godot still uses direct pursuit. No target selection,
damage, navigation, safe zones or network authority changes are made.

The native module tests cover duplicate candidate positions, deterministic
ordering, max-results caps, invalid limits and parity with the legacy
position query. The main game regression exercises two real infected
claiming distinct physical ring slots.

Reference: Unreal EQS scoring and item tests
https://dev.epicgames.com/documentation/unreal-engine/eqs-node-reference-tests-in-unreal-engine

## Inclusive directional dot band (Unreal EQS-style Dot Test)

The directional prefilter now accepts both `min_direction_dot` (default -1) and
`max_direction_dot` (default +1). With `use_direction=true`, only candidates
whose direction cosine is inside this inclusive range survive. This enables
lateral/side sectors while excluding directly forward and rearward positions.
Both bounds are finite and validated in [-1, 1]; setters reject inverted
ranges without changing the resource. The default upper bound keeps all
existing one-sided directional queries unchanged. Every query mode shares the
same geometric prefilter, in 3D or XZ, without physics or navigation calls.

Albion After infected use a -0.25..+0.75 band to approach the sides of prey
instead of selecting a directly far-side ring slot. Older Cgame builds keep
the previous one-sided filter via a `has_method` compatibility guard; stock
Godot keeps ordinary direct pursuit. Authoritative movement and navigation
validation remain unchanged.

Reference: https://dev.epicgames.com/documentation/en-us/unreal-engine/eqs-node-reference-tests-in-unreal-engine

## Native concentric Donut candidate generator (Unreal EQS)

`sample_donut(center, inner_radius, outer_radius, ring_count, points_per_ring,
phase=0.0, spiral=false)` adds a deterministic XZ multi-ring generator,
analogous to Unreal's *Points: Donut* EQS generator. Rings progress inclusively
from the inner to outer radius; a single ring uses the outer radius, identical
to `sample_ring()`. Setting `spiral=true` offsets each subsequent ring to
prevent radial spokes. Sampling is a pure-data operation: it **does not** call
PhysicsServer, NavigationServer, raycasts or scene nodes.

Nonfinite positions, radii and phase, negative/inverted radii, ring counts
outside 1..256, points per ring outside 1..4096, and total allocations greater
than 65536 points fail closed. Callers remain responsible for nav reachability,
terrain height, blockers, safe zones and actor occupancy.

Albion After uses this generator to precompute three 16-site candidate rings
for **server-authoritative raid reinforcements** instead of calculating 48
trigonometric coordinates in GDScript on each request. The existing server
checks and source ordering are retained. Stock Godot and older Cgame builds
still use the previous pure GDScript loop, and game tests verify native/fallback
point positions within floating-point tolerance.

Reference: https://dev.epicgames.com/documentation/en-us/unreal-engine/eqs-node-reference-generators-in-unreal-engine

## Bounded oriented cone candidate generator (Unreal EQS Points: Cone)

`sample_cone(center, direction, inner_radius, outer_radius, ring_count,
points_per_ring, cone_degrees=90.0, include_center=false)` generates an
oriented sector of XZ candidate locations. The input direction's XZ
projection establishes the centerline; `cone_degrees` is the **full**
aperture. Each ring runs from the left edge of the sector to the right
edge, inclusive; a one-ray sector samples the centerline. Radius increases
from inner to outer (one ring uses outer), and `include_center` prepends the
center exactly once.

Generation is deterministic, has no scene/physics/nav side effects and
rejects nonfinite inputs, invalid radii, direction vectors with no XZ
component, angles outside 0..360 degrees, counts outside 1..256 rings or
1..4096 rays, and output allocations greater than 65536 points.

Albion After's raid boss now adds a bounded 2x9 forward sector in the
second reinforcement wave, facing the nearest **server-verified alive**
survivor (ties resolved by position). This supplements rather than
replaces the existing 3x16 donut points. Every added location still
passes the unchanged server-side zone, terrain, water, collision,
player-distance, height, infected-occupancy and multi-threat clearance
checks. A GDScript fallback produces equivalent points on stock Godot
and older engine binaries.

Reference: https://dev.epicgames.com/documentation/unreal-engine/eqs-node-reference-generators-in-unreal-engine

## Native context-facing rectangular grid (Unreal EQS-style grid generator)

`sample_oriented_grid(center, forward, half_extents, spacing, max_points=4096)`
adds a **direction-relative** rectangular grid alongside the old world-aligned
`sample_grid()`. Local +Z aligns with the XZ projection of `forward`, while
local +X points to the actor's right. The grid is emitted in stable row-major
order with unchanged center Y. Supplying a forward axis of `Vector3(0,0,1)` reproduces
`sample_grid()` exactly. The native method validates all inputs, including
direction, extents and bounded point counts, and never touches physics,
navigation, scene nodes or GPU resources.

Albion After uses the grid as a **secondary** search for guards around public
supply drops and dangerous ruin ambush caches when all usable ring candidates
are consumed. The grid aligns away from the closest finite survivor, with an
explicit position tiebreaker and a bounded 5x5 (25-point) budget. Existing
rings always have first priority. Every grid candidate must still pass the
exact same authoritative zone, terrain, slope, water, collision, survivor,
infected and pairwise separation tests as the original guards. Stock Godot
and older engine binaries use a corresponding GDScript fallback.

Inspired by Unreal EQS Points: Grid and context-relative generators:
https://dev.epicgames.com/documentation/en-us/unreal-engine/eqs-node-reference-generators-in-unreal-engine

## Area-uniform golden-angle annulus sampling (procedural radial scatter)

`sample_fibonacci_annulus(center, inner_radius, outer_radius, count, phase=0.0)`
adds an O(N) native **area-uniform annulus** generator to the existing
EQS generators. Rather than choosing radial coordinates linearly or placing
every ring's points along the same spokes, it uses

`radius = sqrt(inner_radius² + ((i + 0.5) / count) * (outer_radius² - inner_radius²))`

and the fixed golden angle `2.39996322972865332` radians per sample.
The center Y is unchanged, the pattern is deterministic with optional
phase rotation, and all output is kept in original source order. Input
radii must be nonnegative and ordered; the algorithm rejects nonfinite
parameters, squared-radius overflow, point output overflow and counts
outside 1..65536. It touches no PhysicsServer, navmesh, scene nodes,
GPU resources or gameplay RNG.

Albion After uses a 32-sample 18..26m scatter as **backup only** for
server-authoritative night horde spawns when the original 3x16
concentric-ring sites cannot fill the requested wave. All original
zone, terrain slope, water, collision, survivor proximity, infected
occupancy, maximum radial distance and inter-enemy spacing checks
apply identically. A GDScript reference fallback preserves older
Cgame / stock Godot. No extra rewards, capacity or client trust.

This is a lightweight Cgame sampling primitive, **not** an implementation
of Unreal's particular node. It is inspired by radial point scatter in
Unreal Dataflow/PCG:
https://dev.epicgames.com/documentation/unreal-engine/node-reference/Dataflow/RadialScatterPoints


## Unreal-style EQS Random Best 5% / 25% without full sorting

`query_random_best_positions(best_percent, seed)` returns an array of zero or
one `Vector3` candidate. Unlike always choosing the highest-scoring item,
this run mode selects **one deterministic pseudorandom candidate** with score
at least `max_score * (1 - best_percent / 100)`. The official Unreal EQS
behavior tree service similarly supports a Random Best 5% (95–100% of max)
and Random Best 25% (75–100% of max) mode.

The engine uses the same filters and weighted scoring as `query()` but
avoids its full sort and intermediate dictionary allocations: pass one
computes the maximum valid score, pass two selects the largest SplitMix64
hash of the caller-owned seed and original candidate index. Cost is
O(N) candidate scoring plus O(1) scratch memory. The selection is repeatable
for identical input, and **does not touch global or server RNG state**.
The percent argument is an integer between 0 and 100; 0 chooses only
best-score ties and 100 chooses from every valid candidate. The return
array is empty when nothing passes (never an unvalidated fallback).

Albion After's regular infected use the 25% random-best selection for
their native EQS tactical flank goal, keyed by the stable infected ID.
This replaces the old top-3 allocation/ranking for **unleased** flank
decisions. The real server's Smart Object branch also tries the seeded
Random Best 25% point first, then retains **every original ranked slot**
as a collision-free fallback. The authoritative slot manager still enforces
priorities, ownership, lease expiry and occupancy; no seeded choice can
create or override a lease. Brutes and bosses still pursue directly. Older Cgame builds keep the
old top-3 path, and stock Godot still follows direct chase. Directional
side-flank filters and cache invalidation remain unchanged.

Official reference:
https://dev.epicgames.com/documentation/unreal-engine/unreal-engine-behavior-tree-node-reference-services

## Count-budgeted EQS work admission across server ticks

`EnvironmentQuery3D.schedule_query_mask(agent_count, tick, regular_budget,
urgent=PackedByteArray())` is a **main-thread, deterministic EQS request
scheduler** modeled on Unreal's `UEnvQueryManager` time-sliced testing.
A stable array of eligible AI agents is supplied by the game: the engine
returns a 0/1 mask of agents permitted to spend expensive EQS work this
tick. This pure method does **not** run or asynchronously resume a query.

Regular work is hard-capped to 0..64 grants per tick. A cyclic window
starts at `(tick * min(budget, N)) % N`, with arithmetic reduced before
multiplication. For an unchanged ordered cohort, each ordinary agent is
admitted once per complete rotation (e.g. N=80, budget=8 => 10 ticks).
Urgent 0/1 flags override the normal quota and cannot consume ordinary
slots; this is intentional to allow immediate recovery from stolen AI
Smart Object leases. Valid inputs are 0..4096 agents, nonnegative tick,
and either an empty urgent mask or exactly N zero/one bytes.
Invalid inputs fail closed. Time is supplied by the authoritative caller,
never by a client or wall clock. Runtime complexity O(N), scratch/output
memory O(N) bytes. **This is a per-tick query count cap, not a CPU time
guarantee**; a single long-running query is still synchronous.

Albion After's `GameServer._budget_eqs_replans` uses this scheduler when
at least 64 infected are active: up to 8 ordinary *flank replans* per
tick. Only eligible, active non-boss chasers within 3.5..14m of a live
survivor compete. Cached goals are kept when valid; a deferred stale
goal falls back to direct pursuit, never stale slot ownership. An
actually preempted or expired claimed slot is urgent and may bypass
the quota. Zombie.think() still advances every tick; target detection,
movement, melee, acid, combat timers and server-owned slot lease
management remain unchanged. Stock Godot/older engine builds retain
the original unlimited flank behavior, and the native scheduler does
not add network state or reward changes.

Unreal reference: https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/AIModule/FEnvQueryManagerConfig

## Incremental top-K EQS (Unreal ExecuteOneStep-style query progression)

Unlike the **per-tick query count** scheduler, these instance methods
split an **individual** EQS query into bounded work over multiple calls:

```gdscript
query.begin_incremental_top_positions(8)
# Each game tick, score at most 3 candidate items.
if query.step_incremental_top_positions(3):
    var source_indices: PackedInt32Array = query.get_incremental_top_indices()
    query.cancel_incremental_top_positions()
```

The engine captures the full EQS scoring state and source candidates at
`begin_incremental_top_positions(count)`. Changes to the live resource
do not alter in-flight scores; cancelling or beginning a new query discards
the old snapshot. Each step scores **at most 1–4096 source candidates**,
including rejected ones. Results remain hidden until the final step, and
match `query_top_positions` and `query_top_indices` (stable index ties,
source identity, filters and `max_results`). On completion, the snapshot
remains available until cancellation. Results are never copied out early.
Work is O(K * candidates) overall and O(K) transient ranked storage; a
snapshot also retains the source query's PackedVector3Array data by
copy-on-write. The API does no physics, navigation, threading or timed
callbacks and does not promise a CPU time deadline.

`get_incremental_random_best_positions(best_percent, seed)` selects a seeded
Random Best item from already scored top-K state in O(K), without a new
full query. To match the original `query_random_best_positions` exactly,
K must retain **all** eligible source items (the game uses K=8 for its
eight flank-ring points). Truncating to a small top-K intentionally narrows
the stochastic candidate pool. This avoids extra full rescoring on the
final work slot.

Albion After enables **three candidates per granted tick** when the
server has 64+ infected. A pending infected flank query continues from
its last candidate on each admitted AI work slot instead of recalculating
all candidates; while pending, direct pursuit and combat continue.
If the target changes or moves too far, the pending snapshot is cancelled,
and the next permitted step starts with authoritative current context.
The existing server-owned eight-regular-query budget still applies,
and urgent displaced Smart Object lease recovery bypasses that count
budget. Near-melee, bosses, dead infected and older native/stock Godot
retain the old behavior. No intermediate candidate is ever allowed to
reserve a server Smart Object slot.

Reference: https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/AIModule/FEnvQueryInstance

## Measured microsecond budgets for resumable EQS

`step_incremental_top_positions_timed(time_budget_us, max_candidates)`
adds real **monotonic-microsecond** time checks between candidate evaluations
to the existing incremental top-K scorer. The same scoring snapshot, ordered
source identities, completed-only output and safety filters are preserved.

```gdscript
query.begin_incremental_top_positions(8)
# Work grant in an authoritative physics tick:
var cap: int = query.suggest_incremental_step_size(120, 8)
var finished: bool = query.step_incremental_top_positions_timed(120, cap)
var scored: int = query.get_incremental_last_step_candidates()
var native_us: int = query.get_incremental_last_step_us()
if finished:
    var original_indices := query.get_incremental_top_indices()
```

The first step samples at most three candidates, then an **observed
microseconds-per-candidate** average suggests larger or smaller batches
with a 20% safety margin. The time cap is 1..1,000,000 microseconds;
candidate cap is 1..4096. The timer is checked *between* candidates,
so a step always makes progress and a single expensive candidate may
overrun its budget. The measured time excludes GDScript overhead and
other scene work. Results, including seeded Random Best selection, stay
independent of device speed and unchanged for complete queries.
There is no background execution or hard real-time guarantee.

In Albion After, 64+ infected activate a **120 microsecond advisory
budget per admitted flank work slot** with up to eight source candidates.
The existing server planner admits at most eight regular requests per
tick (urgent lost leases can bypass this count). Only completed
snapshots may claim Smart Object slots. Server-only `get_eqs_replan_stats`
additionally reports `cpu_us`, `scored_candidates` and `timed_steps`
for the most recent full infected tick. Older engine builds use
the earlier candidate-count path unchanged; gameplay physics and attacks
are never postponed.

Comparison: Unreal EQS manager supports MaxAllowedTestingTime per update:
https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/AIModule/FEnvQueryManagerConfig
Godot native monotonic timer:
https://docs.godotengine.org/en/4.6/engine_details/architecture/common_engine_methods_and_macros.html

## Shared per-tick EQS CPU ledger (Unreal EQS manager-style)

`EnvironmentQueryTickBudget` is a reusable native `RefCounted` which
coordinates **all** AI controllers on the same authoritative main-thread
tick, beyond the previous isolated `EnvironmentQuery3D` 120us step.
Its independent regular and urgent pools use actual measured native
scorer microseconds, so one worker's spending reduces the remaining
allowance for the next worker:

```gdscript
var budget := EnvironmentQueryTickBudget.new()
budget.begin_tick(server_tick, 600, 240)
if budget.try_admit_step(false):
    var allowance := mini(120, budget.get_remaining_us(false))
    var cap := query.suggest_incremental_step_size(allowance, 8)
    var complete := query.step_incremental_top_positions_timed(allowance, cap)
    budget.record_step(query.get_incremental_last_step_us())
```

Quota validation accepts 0..1,000,000us per pool; tick must be
nonnegative. Repeat `begin_tick` with identical arguments in the same
tick is intentionally **idempotent** and cannot refill spent CPU time.
The ledger tracks one pending synchronous step at a time; another
admission is rejected until `record_step(actual_us)` (or
`cancel_pending_step()`). Sub-microsecond measured steps charge at
least one microsecond. An individual source candidate can still
overshoot an allowance: this is a **soft**, not hard real-time cap.
The urgent pool is reserved for contested/expired Smart Object flank
leases and has a separate cap, preventing unlimited bypass.
The ledger has no clock dependency: the native EQS scorer supplies
monotonic elapsed microseconds. No network replication or saves.

Albion After enables this budget for 64..4096 infected with the new
native class. The server instantiates one shared ledger and calls
`begin_tick(tick_count, 600, 240)` before any eligible infected work.
It then preserves the existing rotating up-to-eight regular query-step
admissions; each worker additionally checks the shared ledger directly
before scoring and charges it immediately after. A stale slot is
marked urgent, but is restricted to 240us per tick. The per-step
120us cap remains in force and is tightened to the pool's remaining
allowance. Until complete, an agent pursues directly, never claims
a partial/invalid flank slot. Combat, target selection and simulation
timers are never gated. Older engine builds keep the original per-query
logic. `get_eqs_replan_stats()` reports `global_regular_used_us`,
`global_urgent_used_us`, `global_denied`,
`global_regular_steps`, `global_urgent_steps`, and quotas.

Unreal reference:
https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/AIModule/FEnvQueryManagerConfig
