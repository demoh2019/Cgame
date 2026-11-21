# Deterministic AI update slots — dense infected crowds

The canonical multiplayer simulation in `game/scripts/server/game_server.gd` now uses the native `AIUpdateScheduler` supplied by `modules/behavior_tree/` to spread nonurgent infected target-selection passes over stable simulation-tick slots.

## Why

The server previously ran repeated `Zombie._select_target()` reevaluations in lockstep. For a large group, all agents could re-evaluate on one physics tick even when there was no new urgent stimulus. This feature smooths *when* the same checks run; it does not replace pathfinding or reduce other server logic.

- At **fewer than 128 zombies**, all existing target-selection and combat timing stays unchanged.
- At **128 or more**, `GameServer` lazily creates one shared native scheduler with 4 slots. A stable 64-bit hash maps every infected ID to exactly one slot in every 4-tick cycle. No per-ID state is allocated by the native scheduler, and it does not depend on dictionary order or random seeds.
- Only an existing `think_timer`-due target re-evaluation can be deferred. The server still invokes `Zombie.think()` each tick, so physics-style movement, melee damage, spit warnings, status-effect countdowns, pounce logic and important world events are **never gated** by these slots.
- A zombie's first target scan, active guardian taunt and active damage threat bypass the slot gate. A late scan with `think_timer <= -0.2` also runs immediately, so backlogs cannot grow without bound.
- On stock Godot without `AIUpdateScheduler`, the game runs entirely on its prior GDScript logic. Existing single-NPC tests and other small encounters do not change.

The scheduler's tick index comes from the authoritative `GameServer.tick_count`. Its hashed slot is reproducible across platforms and does not advance `RandomNumberGenerator`, which matters for server replay and consistent tests. The scheduler is independent of wall-clock time and is not a hard CPU budget or a worker-thread system.

## Compatibility with simulation LOD

The concurrently developed `AISimulationLOD2D` remains active. It controls the passive target-scan interval (near, medium, or far) according to viewer distance. **AIUpdateScheduler** operates later: when a scan timer becomes eligible during a very large encounter, it assigns that scan to a deterministic frame phase. Thus these systems are complementary, not replacements. The first passive LOD delay and all existing urgent combat overrides are preserved.

## Stable passive LOD with native hysteresis

Inspired by [Unreal Significance Manager](https://dev.epicgames.com/documentation/en-us/unreal-engine/significance-manager-in-unreal-engine)
and [Mass LOD](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Plugins/MassLOD).
`AISimulationLOD2D.get_hysteretic_interval(distance, near_distance, far_distance,
previous_interval, hysteresis, urgent=false)` keeps the per-agent scheduling
decision stable when a viewer oscillates around a tier boundary.

Albion After calls the shared **stateless** native policy for passive, unengaged
infected only and remembers the nominal interval locally per zombie. The
near boundary is **asymmetric for safety**: as soon as any eligible survivor
enters the original pursuit leash, scanning reverts immediately to 0.25s.
Leaving near can retain 0.25s for up to 4 extra metres. Medium-to-far and
far-to-medium transitions require crossing a 4m margin. An urgent request
always uses the near interval. The existing one-time 16-bin startup spread,
4-slot large-crowd scheduler, movement, attacks, effects, and combat
authoritative checks are untouched.

The API rejects invalid/uninitialized previous intervals and oversized or
nonfinite hysteresis margins by returning the ordinary interval. There is no
native per-agent allocation, no random input, and no network payload.
Older fork binaries fall back to their previous `get_interval()` API; stock
Godot continues its original 0.25s passive AI scans. Native unit tests and
`game/tests/test_ai_update_scheduler.gd` verify distance flapping, urgent
overrides, startup phasing and real survivor reacquisition.

## Native crowd separation for idle packs

Inspired by the data-oriented neighborhood steering in Unreal Engine
[Mass Avoidance](https://dev.epicgames.com/documentation/en-us/unreal-engine/mass-avoidance-overview-in-unreal-engine),
the existing `AIProximityGrid2D` has a new stateless native method:

```gdscript
var steering: PackedVector2Array = grid.query_separation_batch(
    zombie_xz_positions, passive_indices, 2.5, 3.0, 8)
```

It performs the same bounded 3×3 hashed-cell, closest-eight-neighbor
selection used by native pack alerts. Each source gets one deterministic,
finite repulsion vector with length at most one; overlapping NPC positions
use stable source indices to choose opposite directions instead of a
random nudge. Malformed requests return an empty array, never partial results.

The canonical multiplayer server shares this native grid with pack alerts.
For 32–1,024 infected it samples passive crowd avoidance **once per five
simulation ticks** (4Hz at the game's 20Hz tick), and only for
`WANDER`/`INVESTIGATE` infected. Nearby active infected are still
obstacles but never receive avoidance-driven combat movement. The game
blends at most 35% repulsion into these two passive movement directions,
using the existing world collision sweep and wounded movement speeds;
it never alters attack checks, target selection, chase, bosses, snares,
knockback, network packets or authoritative player data.

Stock Godot and older Cgame binaries leave previous movement unchanged,
and the server immediately clears steering when the population drops below
32. `GameServer.get_crowd_separation_stats()` is a server-only,
read-only diagnostic snapshot of active calculation and source counts;
it is not sent to connected players.

Native regression tests cover coincident and negative coordinates,
deterministic repeatability, distant NPCs, neighbor limits and invalid
input. `test_ai_update_scheduler.gd` exercises real `GameServer`
batch calculation, threshold cleanup and noncombat-only steering.
An actual compiled Cgame editor is necessary to run the new C++ logic;
no unmeasured FPS or CPU benefit is claimed.

## Predictive Mass-style passive crowd steering

The native `AIProximityGrid2D.query_predictive_separation_batch(
positions, velocities, source_indices, radius, cell_size, max_neighbors,
horizon)` adds a **short forward prediction** to the previous static
nearest-neighbor separation. It builds the same bounded 3×3 spatial
grid on the desired position `position + velocity * horizon` and scores
only the closest `max_neighbors` future neighbors. When two future
positions coincide or pass very closely because of opposing velocities,
deterministic perpendicular steering guides agents to opposite sides
instead of pushing them backward. Stationary exact overlaps still use stable
index-based tie breaking.

The horizon is limited to **0..2 seconds**, velocities to 50 m/s and
the old radius, source, coordinate and neighbor limits remain in
force. Nonfinite and excessive inputs fail atomically. Horizon zero
returns the previous static method's result exactly; no scene or
physics mutation occurs in C++.

Albion After's actual `GameServer` now derives desired velocities
from each `WANDER` or `INVESTIGATE` actor's existing destination and
movement speed, and queries **0.75 seconds ahead** in its already
existing four-times-per-second crowd pass. Rooted/staggered infected
and active combatants have zero predicted velocity; only passive,
non-boss infected receive steering. The same existing 35% mixing and
world collision sweep apply. Combat, AI targets, player positions,
attacks, authority and networking remain unchanged.

The server retains `query_separation_batch` as an opt-in fallback
for older Cgame binaries or invalid predictive requests. Stock Godot
leaves movement untouched. `get_crowd_separation_stats()` now reports
a server-only `predictive` boolean. Native tests verify head-on
sidestepping, zero-horizon parity, moving-apart behavior, stationary
overlaps and invalid inputs. The game test runs a real 32-NPC server
tick with opposing passive destinations.

References: [Unreal Mass Avoidance](https://dev.epicgames.com/documentation/unreal-engine/mass-avoidance-overview-in-unreal-engine)
and [Unreal Avoidance Manager's prediction horizon](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/UAvoidanceManager).

No measured FPS or CPU improvement is claimed without runtime benchmarks.

## Native nearest-EQS query for multiple sensory sources

Following [Unreal's EQS distance-based item selection](https://dev.epicgames.com/documentation/unreal-engine/eqs-node-reference-tests-in-unreal-engine)
and its data-oriented
[Mass Entity queries](https://dev.epicgames.com/documentation/unreal-engine/overview-of-mass-entity-in-unreal-engine),
the reusable Cgame `AIProximityGrid2D` now supports:

```gdscript
var indices: PackedInt32Array = grid.query_cross_nearest_batch(
    observer_positions, cue_positions, persistent_cue_ids, 23.0, 23.0)
# indices[i] is the ORIGINAL cue index or -1 when no cue is nearby.
```

The method builds a 2D spatial hash for the candidate cues and performs
at most nine cell visits per observer. The exact inclusive radius is checked
before selecting the closest item; **equal-distance candidates are ordered
by their persistent world ID**, then the original input index. This keeps
the returned identity stable when two separate cues share a location.
It does not allocate a Dictionary for each result, query scene nodes,
perform line-of-sight tests, change any target, or authorize an attack.

All inputs are validated before selecting results. Bounds: at most 4,096
observers and 8,192 cues, finite coordinates within ±1,000,000 units,
radius 0..256m, and cell edge 1..256m with edge >= radius. An invalid
request yields an **empty** packed array; a valid unmatched source gets
an index of **-1**. This distinction allows a safe GDScript fallback.

Albion After's canonical server now uses the same C++ selector for
three independently authorized stimulus categories:

- **Thrown noise decoys**: already validated as active and audible.
- **Corpse blood scent**: only server-confirmed death bags, unlooted
  and before both expiry deadlines.
- **Night campfire light**: only current, active nighttime light sources.

The existing GDScript cell indices still validate expiry and eligibility.
When there are **32..4096 infected and at least 4 active cues** in the
specific sense, the server chooses one closest source for every living
non-boss infected in a single C++ call. The last-mile gameplay behavior is
still `Zombie.investigate_decoy`: combat priority, investigation lock,
pursuit leash, and boss immunity are unchanged. The query never invents
a player source or conveys private world state to clients.

If the C++ method is unavailable, the cohort or cue count is small, or
the request is invalid, each category retains the existing authoritative
GDScript nearest-bucket selection. A server-only
`GameServer.get_ai_cue_query_stats()` report records which channel used
the native path and how many sources/cues were considered.

Native doctests cover equal distances, duplicate target positions and
IDs, negative cells, exact zero and positive radii, duplicate observers,
missing matches and oversized/malformed inputs. The live game regression
compares all **three** sensory channels between native and forced scalar
fallback on the same 32-zombie encounter, including a boss, a chasing
infected, two equal-distance sources and a distant bystander.

No latency, FPS or CPU improvement is claimed without a compiled native
engine and repeatable benchmarks.

## Batched vertical-cylinder presence for camp sentries (Mass-style)

Inspired by Unreal's data-oriented [Mass Entity processors](https://dev.epicgames.com/documentation/unreal-engine/overview-of-mass-entity-in-unreal-engine), Cgame exposes a new spatial-hash primitive that handles many 3D proximity counts in one native call:

```gdscript
var counts: PackedInt32Array = grid.query_cylinder_counts_batch(
    alarm_world_centers, living_infected_positions,
    21.0, 8.0, 5)
```

The query hashes **target XZ coordinates once**, then visits the target
cell and at most its eight adjacent cells per source. Each match
must lie within the inclusive horizontal radius **and** the inclusive
absolute Y difference. The result is a packed array of counts in
source order, clamped to `max_count`, with no entity IDs or private
coordinates in the result. It does not alter scene state or trigger
physics or gameplay events.

Bounds: 1..4096 source cylinders, 0..8192 targets, finite coordinate
magnitudes no greater than 1,000,000, radius 0..256, height 0..256,
and a count cap in 1..64. An empty target set yields valid all-zero
counts; malformed or oversized requests return an **empty** array,
distinct from successful zero detections. Zero radius supports
coincident XZ positions, and exact height/radius boundaries match.

### Live Albion After integration

The canonical multiplayer `GameServer._tick_world()` batches counts
when at least 32 infected and four armed, scan-due, player-owned camp
alarms coexist (up to 8192 infected / 4096 alarm centers). Its query
snapshot contains only living infected with finite positions; **raid
bosses are counted**, matching previous alarm rules. A server-only
`get_camp_alarm_query_stats()` reports whether this optimization ran.

The old `CampAlarm.scan(fire, zombies, now)` is still the authoritative
timer, fuel and alert-cooldown gate. It accepts an *optional* precomputed
count only when provided by the server's valid native batch; otherwise
the same 3D exhaustive loop runs unchanged. A native result is fully
validated for size and count range before any game state is mutated.
Weather dousing, expired fires, missing alarm owners and disconnected
players still suppress notifications. A single alarm reports at most
five nearby infected and preserves its two-second scan interval and
24-second alert cooldown.

Tests include C++ cylinder queries (boundary distance, vertical floors,
negative cells, no enemies, zero radius, duplicate observers, caps and
malformed arrays), plus a real `GameServer._tick_world()` scenario with
four alarms and 32 infected. The game regression compares native and
forced old-engine paths for identical event counts, authoritative
per-alarm schedules, boss presence and altitude exclusion.

This optimization is an additive Cgame API, **not a port of Unreal
engine code**. No measured CPU or FPS improvement is claimed without
native compilation and repeatable benchmarks.

## Inspect the real server

The diagnostic `GameServer.get_ai_schedule_stats()` method returns a detached Dictionary:

| Key | Description |
| --- | --- |
| `enabled` | Native staggering is active at the population threshold |
| `population` | Infected count after this tick's population maintenance |
| `slots` | Number of scheduling phases (4 when enabled, otherwise 1) |
| `phase_due` | Target-scan candidates admitted to this tick's hash slot |
| `phase_deferred` | Target-scan candidates assigned to other slots |

The phase counters are **scheduler admissions, not actual executed scans**. Urgent and first-contact checks can still run despite a deferred phase. This method is server-side diagnostics only; do not replicate to public clients.

For the engine API itself:

```gdscript
var scheduler := AIUpdateScheduler.new()
scheduler.slots_per_cycle = 4
var should_reconsider: bool = scheduler.is_due(zombie_id, server_tick, urgent_event)
var remaining_ticks: int = scheduler.ticks_until_due(zombie_id, server_tick)
```

The playable `modules/behavior_tree/demo_reactive_ai/` now uses the same native scheduler to spread **A* path replanning** when a moving goal enters another grid cell. A changed AI action triggers an immediate replan; the old safe path is reused between slots. Real repath durations are measured using `AIExecutionProfiler` and shown in its HUD.

## Tests

Native: `modules/behavior_tree/tests/test_ai_update_scheduler.h` checks repeatability, per-agent fairness, urgent overrides, slot distribution, range validation and wait-to-next-slot calculations.

Main game: `game/tests/test_ai_update_scheduler.gd` is included in `game/tests/run_all.gd` and checks initial contact, combat threat priority, the 128-NPC server threshold and the fallback on stock Godot. The demo has a headless route-rescheduling regression.

```sh
scons platform=linuxbsd target=editor tests=yes -j"$(nproc)"
./bin/godot.linuxbsd.editor.x86_64 --headless --test
./bin/godot.linuxbsd.editor.x86_64 --headless --path game --script res://tests/run_all.gd
./bin/godot.linuxbsd.editor.x86_64 --headless --path modules/behavior_tree/demo_reactive_ai --script res://tests/smoke_navigation_hearing.gd
```

This work follows the spirit of periodic services in Unreal's Behavior Trees and Godot's recommendation to avoid unnecessary repeated navigation queries. It does **not** incorporate code from another engine.

## Limits

Time-slot staggering does not parallelize AI or guarantee a particular frame-time improvement. Evaluate its effect using the existing `AIExecutionProfiler` and the server-side metrics before tuning slots or the population threshold. Avoid scheduling urgent combat actions or player-protection decisions.
