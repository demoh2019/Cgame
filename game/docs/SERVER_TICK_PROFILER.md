# Server Tick Profiler & Adaptive Incident Governor

This feature is **wired into the canonical multiplayer game server** at
`game/scripts/server/server_main.gd` and
`game/scripts/server/game_server.gd`. It is not an isolated lab demo.

## What the engine extension does

`scripts/server/server_tick_governor.gd` is a reusable, bounded,
server-owned recorder for the duration of actual authoritative simulation and
network work (`net.server_tick(delta)`). It measures each server physics
tick with `Time.get_ticks_usec()` and maintains up to **200 samples** in a
circular buffer. The server logs the CPU-side **p95 tick duration** every 10
seconds alongside its existing full-tick maximum, player and infected counts,
and the live incident-spawn cap.

A second, conservative feedback loop measures p95 over **20 active-player
ticks** (one nominal second at 20 TPS). A window is considered overloaded
when p95 exceeds **45 ms** (90% of the 50 ms 20-TPS target). After **three**
consecutive overloaded windows the cap for **new random incident enemies** is
reduced by two (floor 2). After **five** consecutive windows below 30 ms
(60% of the target), the cap increases by one (ceiling 10). The dead zone
prevents oscillation. Empty-server ticks reset consecutive evidence; invalid
timings are rejected. Adaptation can be disabled.

The governor only changes `GameServer.incident_spawn_cap`, which is applied
after the existing
`WorldEncounterDirector.spawn_budget()` (zone, HP, nearby enemies, global
limits). The resulting cap trims *new* horde/cache/screamer reinforcements.
It does **not** skip existing enemies' AI updates, physics, player movement,
damage validation, PvP, save checkpoints or network snapshots.

The default mode is automatic. To disable it and retain the previous
maximum incident cap, start the dedicated server with:

```bash
godot --headless --path game --script res://scripts/server/server_main.gd -- --port 24565 --seed 1337 --fixed-incidents
```

### Reading the server log

A typical log format (illustrative, not a benchmark result):

```text
SERVER players=4 zombies=58 bags=11 tick_max=52.00ms sim_p95=37.00ms incident_cap=8 adaptive=ON
```

- `tick_max`: wall-clock processing duration measured around the full
  dedicated-server physics handler, including optional checkpoint writes;
  reset after each 10-second log.
- `sim_p95`: nearest-rank p95 of **up to 200 recent**
  server `net.server_tick` durations, excluding subsequent disk checkpoint
  work, but including network/simulation operations inside the call.
- `incident_cap`: temporary upper bound on new random event enemies;
  **not** a cap on total enemies already alive.
- `adaptive`: whether feedback is enabled (`--fixed-incidents` disables).

These are **CPU-side wall-clock timings, not GPU times** and do not constitute
measured proof of higher frame rate. Since the game uses a dedicated
server, client rendering FPS is separate.

## Testing

```bash
godot --headless --path game --script res://tests/run_all.gd
```

`test_server_tick_governor.gd` exercises bounded history/eviction,
nearest-rank p95, invalid samples, no-player behavior, sustained overload,
hysteresis, gradual recovery, a manual fixed mode, and a real
`GameServer._tick_world_incidents()` suppression without ghost events.
This test is **registered in the canonical `run_all.gd` suite**.

**Validation limitation:** the authoring environment has no working Godot
executable, so these new GDScript tests are not yet runtime-verified. No
performance improvement on any hardware is claimed. Inspect the game server
logs and run benchmarks on the intended production host before adjusting
thresholds.

References:
- [Godot 4.6 CPU optimization](https://docs.godotengine.org/en/4.6/tutorials/performance/cpu_optimization.html)
- [Unreal Engine Mass Gameplay overview](https://dev.epicgames.com/documentation/unreal-engine/overview-of-mass-gameplay-in-unreal-engine)
- [Unreal animation budget allocator](https://dev.epicgames.com/documentation/unreal-engine/animation-budget-allocator-in-unreal-engine)

## Native Cgame engine service (November 2026)

`scene/main/adaptive_tick_governor.{h,cpp}` now provides the reusable
**AdaptiveTickGovernor** C++ `RefCounted` class. It implements the same
200-tick ring, nearest-rank p95, 20-tick active windows, sustained 90%/60%
CPU pressure thresholds, 3-window overload/5-window recovery hysteresis
and 2..10 optional-work budget as the original game script.

Reusable engine API:
- `observe_tick(elapsed_usec: int, active_users: int)` for validated CPU
  measurements, without ever skipping any mandatory game simulation.
- `get_budget_units()` for the caller's own optional workload (for Albion
  After, only **future random incidents**).
- `set_enabled(bool)`, `snapshot()`, `get_history_count()`,
  `samples_oldest_first()`, and `reset()`.
- `set_target_tick_ms(ms)` and `set_budget_range(min, max)` let other
  Cgame applications choose their own tick rate and optional work range.

`game/scripts/server/server_main.gd` automatically uses the native class
on Cgame and keeps `ServerTickGovernor` as a feature-compatible fallback
for stock Godot. No changes are required to network snapshots, ongoing
infected AI, actual player physics, combat or disk persistence.

`tests/scene/test_adaptive_tick_governor.cpp` tests native history, invalid
and idle samples, hysteresis, disabled mode and configuration; the existing
`game/tests/test_server_tick_governor.gd` now also checks native/script
parity and bounded ring ordering. The dedicated GitHub Actions workflow
`.github/workflows/native-adaptive-tick-governor.yml` compiles Cgame with
native tests and runs Albion After's full GDScript suite.

Design context: Unreal Mass Gameplay LOD and Unity DOTS use relevance and
data-oriented work budgeting to focus CPU time on valuable work.
References:
- https://dev.epicgames.com/documentation/unreal-engine/overview-of-mass-gameplay-in-unreal-engine
- https://learn.unity.com/article/c-and-dots-specific-performance-tips

Neither build/test results nor an FPS/server-throughput improvement are
claimed until a native CI run actually succeeds.
