# Behavior Tree module (runtime MVP)

This optional, built-in Godot module provides the **runtime foundation** of a
behavior tree system for gameplay AI. It is not a visual graph editor yet.
When enabled, all resources are available in the scene inspector and in
GDScript. The module has no third-party runtime dependencies.

## Included resources

- `BehaviorTreeSequence`: run children in order, stop at the first failure,
  resume the running child without repeating previous actions.
- `BehaviorTreeSelector`: try alternative branches until one succeeds, resume
  a running branch.
- `BehaviorTreeInverter`: swap success and failure (preserve running).
- `BehaviorTreeBlackboardCheck`: compare a blackboard key with a value.
- `BehaviorTreeBlackboardSet`: set a blackboard key.
- `BehaviorTreeWait`: wait for a duration with runner-local state.
- `BehaviorTreeTask`: script-extensible base class.
- `BehaviorTreeRunner`: one instance per AI agent with an independent
  blackboard and execution memory; manual or automatic frame ticking.

## GDScript usage

Add a `BehaviorTreeRunner` node to a scene, then assign a
`BehaviorTreeSequence` resource to its `root_task` property. Add a
`BehaviorTreeWait`, `BehaviorTreeBlackboardCheck` and
`BehaviorTreeBlackboardSet` as child resources in the inspector.

You can also assemble the tree from script:

```gdscript
extends Node

@onready var ai: BehaviorTreeRunner = $BehaviorTreeRunner

func _ready() -> void:
    var sequence := BehaviorTreeSequence.new()
    var wait_task := BehaviorTreeWait.new()
    wait_task.duration = 0.2

    var set_task := BehaviorTreeBlackboardSet.new()
    set_task.key = "can_attack"
    set_task.value = true

    sequence.add_task(wait_task)
    sequence.add_task(set_task)
    ai.root_task = sequence
    ai.auto_tick = true
```

To create a custom scripted behavior task:

```gdscript
extends BehaviorTreeTask

func _tick(blackboard: Dictionary, delta: float) -> int:
    if not blackboard.get("target_visible", false):
        return FAILURE
    # Perform or schedule a custom action here.
    return SUCCESS
```

`_tick` must return `SUCCESS`, `FAILURE`, or `RUNNING`. A runner stops
on completion and emits `tree_finished(status)` once. Call `reset()` to
repeat the tree; the blackboard remains intact. An unassigned root returns
`FAILURE` but does not permanently finish the runner.

## Concurrency and determinism

A single task resource can be shared by multiple agents or used multiple
times in one tree. Each `BehaviorTreeRunner` stores its own execution
cursors, and each occurrence of a task has its own position-based state.
Only user-supplied blackboard data is mutable across scripts; do not store
agent state on shared task resources.

Cycles in the built-in task graph are rejected. Each task executes
synchronously for a single tick and must not block the main thread. For
long-running work, return `RUNNING` and poll completion on later ticks.

## Tests

Build Godot with the module enabled and the standard test suite:

```shell
scons platform=linuxbsd target=editor dev_build=yes tests=yes module_behavior_tree_enabled=yes
bin/godot.linuxbsd.editor.dev.x86_64 --headless --test --test-case="*[BehaviorTree]*"
```

These tests cover execution order, short-circuiting, running/resumption,
blackboard data, nested composites, cyclic-graph protection, multiple
agents, signals, automatic ticking, and resource serialization.

## Planned extensions

The runtime provides a foundation for a **graph editor** (the requested
editor experience), more leaf tasks, AI perception, asynchronous actions,
debug visualization, and StateTree-style hierarchy. Those are not
implemented by this first PR.

## Opt-in ranked hearing memory

`AIHearingSensor2D.report_noise_ranked(listener, source, loudness, occlusion=1.0)`
preserves the clearest of several already-audible events during its memory
window, instead of overwriting the last-heard position on each report.

- Clarity is normalized `max(0, 1 - distance / effective_radius)`;
  `effective_radius = hearing_radius * loudness * occlusion`.
- The strongest audible source wins. Equal scores use world position
  lexicographic order (X then Y), independent of event iteration order.
  Reports from the current winning source refresh memory when their
  score is unchanged. Weaker reports return `true` (heard), but do not
  overwrite or refresh memory.
- Strength is exposed through `get_last_heard_strength()`. It is
  cleared when memory expires or is reset. Invalid coordinates and
  multipliers are rejected.
- Existing `report_noise()` retains its original last-event-wins
  behavior for compatibility, while clearing optional ranked strength.
- Nothing is heard unless the game explicitly reports a sound. The
  engine never performs automatic LOS, wall attenuation, PvP checks,
  team checking or client-owned sensory updates.

Albion After calls the ranked method **only** when available; stock
Godot and older Cgame continue their previous behavior.

## Multi-source AI event memory

`AIStimulusHistory2D` is a native RefCounted history for events **already confirmed by the game**. Each memory entry stores its sense (visual, sound, damage), source ID, position, normalized strength and expiry. Repeated identified sources update in place; anonymous sources remain independent. A 16-entry default / 64-entry maximum ensures predictable memory usage per agent.

```gdscript
var history := AIStimulusHistory2D.new()
history.record_stimulus(AIStimulusHistory2D.SOUND, heard_at, 0.85, 3.5, peer_id)
history.advance_time(0.2)
var top_sound: Dictionary = history.get_best(AIStimulusHistory2D.SOUND)
var recent: Array = history.get_recent(8) # Detached diagnostics
```

Ranking multiplies signal strength by its fraction of remaining lifetime; ties are broken deterministically by source ID and position. This is not an ambient automatic perception system: **no source enters the history unless the game explicitly records it**. See `game/docs/NATIVE_AI_PERCEPTION.md` for canonical Albion After integration, including investigation of an independently confirmed secondary sound.

## Native simulation LOD for crowds and server AI

`AISimulationLOD2D` is a reusable RefCounted cadence policy inspired by the
variable-frequency crowd AI update budgets in Unreal MassGameplay and the
distance-based simulation LOD guidance in Unity.

- `get_interval(distance, near_distance, far_distance, urgent=false)`
  returns 0.25 s, 0.5 s or 1.0 s at inclusive near/far thresholds.
  These can be changed **atomically** with `configure_intervals`, which
  enforces `0 < near <= medium <= far <= 2` seconds.
- `get_staggered_interval(agent_id, ...)` provides an optional one-time
  deterministic 16-bin phase. Call it only for the first passive schedule,
  then use `get_interval`; do not phase urgent/near AI.
- Positive infinity means no eligible viewers; invalid distance/thresholds
  conservatively return the near update frequency.
- The API selects **when to run a caller-owned expensive AI step**. It
  does not change frame delta, pause simulation, fake physics, move agents,
  skip damage or override network authority.

Albion After uses this natively for **passive, unengaged infected target
selection only**; active chases, combat, per-frame movement and status
timers continue at their original rates. Stock Godot uses the previous
0.25-second target scan cadence.

Source concepts:
https://dev.epicgames.com/documentation/unreal-engine/overview-of-mass-gameplay-in-unreal-engine
https://docs.unity.cn/Manual/CullingGroupAPI.html
