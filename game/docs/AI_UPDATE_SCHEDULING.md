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
