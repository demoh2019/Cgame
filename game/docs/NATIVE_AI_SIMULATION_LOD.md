# Cgame native AI simulation LOD in Albion After

This release adds `AISimulationLOD2D` as an opt-in native **frequency
policy** for high-population games. It does not implement an ECS, a new
navigation solver, or artificial approximation of combat. The design
borrows the *variable-frequency simulation LOD* concept from Unreal
MassGameplay, and Unity's distance-based AI simulation LOD guidance.

References:
- Unreal Engine: https://dev.epicgames.com/documentation/unreal-engine/overview-of-mass-gameplay-in-unreal-engine
- Unity: https://docs.unity.cn/Manual/CullingGroupAPI.html

## Engine API

```gdscript
var lod := AISimulationLOD2D.new()
lod.configure_intervals(0.25, 0.5, 1.0)
var cadence := lod.get_interval(distance_to_closest_viewer, 30.0, 60.0)
var first_delay := lod.get_staggered_interval(agent_id, distance_to_closest_viewer, 30.0, 60.0)
```

Distance <= near threshold returns 0.25 s. Near < distance <= far
returns 0.5 s; farther returns 1.0 s. Positive infinity is permitted
as "no eligible viewers". Invalid inputs return the fastest cadence.
`urgent=true` always returns the fastest cadence.

`get_staggered_interval` distributes the **first** passive update
among 16 stable ID-based slots: no RNG, shared mutable state or
zero-duration recurrence. Call it once for a distant agent and
`get_interval` thereafter. An invalid negative ID cannot delay AI.

Settings are atomically configurable; 0 < near <= medium <= far <= 2 s.

## Live game integration

Albion After's server-authoritative infected state machine calls this
native policy only after a completed **passive target selection**. The
existing selector already iterates eligible living, unsafe survivors;
it now reports the closest distance as well. There is no extra global
scan and no extra physics query.

- A survivor at or inside `data["lose"]` keeps the original 0.25-s
  target acquisition cadence. Between that distance and +24 metres
  the scan runs every 0.5 s, and farther away every 1.0 s.
- A stable zombie ID spreads the **first** distant scan over 16 slots.
  Further distant scans use the full selected interval.
- Active chasing and attacking, raid bosses, taunts, pack alerts and
  combat threat continue at their existing cadence. Tick-based
  movement, damage, attack timers, stagger, bleeding, windups, etc.
  still execute every authoritative server tick.
- If a survivor suddenly approaches a passive faraway infected,
  first acquisition can be delayed by **at most 1 second**. Existing
  explicit alerts and combat acquisition are not delayed.
- On a stock Godot installation without the Cgame class, the game
  retains the original 0.25-second passive scan rate.

### Validation

- Native C++ regression tests for tiers, boundaries, urgent priority,
  deterministic phasing, invalid inputs and configuration rollback.
- Canonical `game/tests/test_zombie_ai.gd` asserts near/remote/fallback
  behavior and that pack alert interrupts passive LOD.
- Full game suite already includes this test in `game/tests/run_all.gd`.
- Native CI workflow added to compile and exercise the engine, import
  scripts and run the canonical game tests.

This change is a cadence policy, **not a claimed benchmark result**.
Measure the overall server AI cost with `AIExecutionProfiler` and an
identical seed/player population before claiming a speedup.
