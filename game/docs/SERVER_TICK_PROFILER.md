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
