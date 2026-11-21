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
