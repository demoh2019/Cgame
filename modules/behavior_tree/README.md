# Behavior Tree module (runtime MVP)

This optional, built-in Godot module provides the **runtime foundation** of a
behavior tree system for gameplay AI. It is not a visual graph editor yet.
When enabled, all resources are available in the scene inspector and in
GDScript. The module has no third-party runtime dependencies.

## Visual BehaviorTree Inspector: editor dock and runtime tree

The native `BehaviorTreeRunner.get_tree_snapshot()` now returns the **full task hierarchy** even for branches that were not run on the last tick. It merges on-demand `AIBehaviorTrace` statuses into stable Resource paths, distinguishes `NOT RUN` from `SUCCESS`, `FAILURE` and `RUNNING`, and includes inclusive CPU time per visited node. Maximum 256 task nodes, with a graph-truncation flag; no per-frame tree walk when unused.

Two editor-ready addon copies live at `game/addons/cgame_bt_debugger/` and `modules/behavior_tree/demo_reactive_ai/addons/cgame_bt_debugger/`, enabled in both Godot project files. The **Cgame AI** right-hand editor dock inspects a selected `BehaviorTreeRunner` in the edited scene (or the first runner under the scene root), with Refresh, colored statuses and resource paths. It safely reports a missing native class on stock Godot. This editor view **does not attach to the remote running game's process**; live per-tick behavior appears in the demo's runtime inspector panel.

The playable sandbox now includes a live `Tree` UI with status colors, execution times and nested Resource tasks, shown only when **T** enables tracing. The canonical game uses a GDScript zombie state machine rather than a BehaviorTree, and exposes compatible **server-only** `Zombie.get_ai_state_visual_snapshot()` data showing its actual active state and last traced target-selection phase. These debug APIs are not network RPCs and must not be forwarded to multiplayer clients.

## Opt-in per-node AI execution tracing

`AIBehaviorTrace` brings a bounded per-task execution history to Cgame's native Resource behavior trees. This implements a practical part of the debugging workflows seen in Unreal's Behavior Tree debugger and LimboAI's runtime inspector: each executed task records its **path, class, returned status, tree depth and inclusive CPU time** in start order. It retains only the latest tick (128 steps by default, up to 256), with an explicit `truncated` count for oversized trees.

```gdscript
var brain: BehaviorTreeRunner = $BehaviorTreeRunner
brain.trace_enabled = true                  # Opt-in; default is false.
brain.tick(0.2)
var trace: Dictionary = brain.get_trace_snapshot()
for entry in trace.get("steps", []):
    print(entry["path"], " | ", entry["task_class"],
          " | result=", entry["status"], " | usec=", entry["duration_usec"])
brain.reset_trace()
brain.trace_enabled = false
```

Only the selected runner allocates trace storage and calls the CPU clock for individual tasks. Tracing is independent of `profiling_enabled`, which tracks aggregate execution time. Shared task Resources do not share trace data; each agent has its own memory. The runner's `get_debug_snapshot()` now includes a detached `trace` record alongside the Blackboard and execution memory. **Do not forward internal AI decision traces or Blackboard data to ordinary multiplayer clients.**

The playable AI demo enables trace initially and uses **T** to toggle per-node recording. Albion After also integrates the underlying `AIBehaviorTrace` with its authoritative zombie state machine for optional timing of real target selection, through `Zombie.enable_ai_trace(true)` and server-side `get_ai_trace_snapshot()`. No gameplay logic or random-number generation is changed by enabling traces.

This is a bounded inspection API, not yet a graphical dock in the Godot editor or an offline history of every past tick. Scripted task internals are opaque; each scripted task is shown as one node when executed through native composites.

## Native timed decorators and action cooldowns

Cgame now provides `BehaviorTreeDecorator` as the cycle-safe single-child Resource foundation, plus two reusable task decorators familiar from Unreal Engine Behavior Trees and Godot LimboAI.

- `BehaviorTreeTimeout` limits a child to a configurable number of simulated seconds. At or after its deadline, it returns `FAILURE` and clears the entire running child subtree without affecting siblings.
- `BehaviorTreeCooldown` triggers a cooldown only after its child returns `SUCCESS`. During the lockout it returns `FAILURE` without calling the child. A `RUNNING` or failing child does not start its cooldown. The timer is **runner branch-scoped**: preemption or runner reset erases it.
- `AIActionCooldowns` is a separate native per-agent RefCounted event gate for named **gameplay actions** across tree restarts. `try_trigger("pack_howl", 6.0)` admits one event and rejects additional attempts until `advance_time(delta)` expires its timer. There is no wall-clock dependency or global state, and each instance holds at most 16 action keys.

```gdscript
var timed_search := BehaviorTreeTimeout.new()
timed_search.duration = 0.8
var search_task := BehaviorTreeWait.new()
search_task.duration = 2.0
timed_search.task = search_task
# Insert timed_search as a child of a BehaviorTreeSequence/Selector.

var actions := AIActionCooldowns.new()
if actions.try_trigger(&"pack_howl", 6.0):
    notify_nearby_allies()
actions.advance_time(server_delta)
```

Albion After integrates the event gate into the *authoritative howler pack alert*, and the playable behavior-tree demo uses Timeout on audio investigations and action cooldowns on the player's shout. On stock Godot, Albion After keeps its prior one-howl-per-target behavior; the standalone native demo requires Cgame.

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

## Native batched AI target-scan scheduling

`AIUpdateScheduler.get_due_mask(PackedInt64Array agent_ids, int tick_index)`
returns a `PackedByteArray` with one admission bit (0 or 1) at the same
array index. It reuses the exact scalar `is_due` hashing and slot cycle,
including signed agent IDs and duplicate IDs. Its only benefit is to move
a full cohort of deterministic slot checks through **one GDScript/C++ call**;
the packed input/output allocation still has a cost, so benchmark actual
frame time before claiming a speedup.

- At most 4096 agent IDs; negative tick or larger input returns an empty
  array, allowing the caller to use the old scalar method.
- Stateless and reproducible; the result does not grant target acquisition
  or move an agent and does not override urgent `is_due(..., true)`.
- Albion After's authoritative `GameServer._tick_zombies()` snapshots its
  current infected cohort once per tick and consumes the native byte mask
  by **matching array index**. Combat, movement, invulnerability checks,
  perception urgency, target reevaluation and all normal `Zombie.think`
  calls still occur on every simulation tick. Older fork binaries fall
  back to the scalar per-infected API, stock Godot retains the original
  non-staggered behavior.
- Server-side `get_ai_schedule_stats()` reports `batch_used`,
  `batch_size`, and the existing admitted/deferred scan counts. These are
  diagnostics, not a network protocol change.

Concept references: Unreal Engine MassEntity chunk processors and Unity
Entities IJobEntity; no external code was copied or used.

## Native MMO threat / aggro arbitration

`AIThreatTable2D` provides reusable, stateless-in-the-engine native
threat accumulation, aging and protected-target filtering over an NPC's
caller-owned `Dictionary`:

```gdscript
var table := AIThreatTable2D.new()
var hate := {} # each NPC owns its own table
table.record(hate, attacker_id, actual_server_damage)
table.decay(hate, delta)
var best_peer_id := table.pick(hate, server_players, enemy_xz, max_leash, current_peer_id)
```

Threat is capped at five participants / 10,000 points, ages at 0.75
points per second, and changes target only when a challenger reaches
1.25 times current hate. Ties use the **lower peer ID** deterministically,
independent of Dictionary insertion order. Invalid, safe, dead and
unreachable participants are removed during target selection.

Albion After's existing `scripts/shared/threat.gd` negotiates this class
once and calls its methods from the authoritative infected state machine,
with a GDScript reference fallback on stock Godot. Source identities,
damage validation, safe-zone authority and network synchronization remain
entirely game-owned. No native threat data is sent to ordinary clients.

See `game/docs/NATIVE_AI_THREAT_TABLE.md`.

## Bounded native 2D pack proximity grid

`AIProximityGrid2D.query_radius_batch(positions, source_indices, radius, cell_size)`
builds one temporary spatial hash for the supplied 2D point cohort and returns
one `PackedInt32Array` of neighbor indices per source (ascending input index,
excluding the source itself). Inputs may use negative coordinates, exact radius
boundary hits are included, and repeated source IDs give repeated results.
With `cell_size >= radius`, only nine cells need inspection per source.
The native method performs the geometric broadphase only, never physics/LOS,
combat authority, server targets, or autonomous movement.

The method limits positions to **8192**, sources to **1024**, radius to
**0–256** and cell size to **max(1,radius)–256**, with finite bounded world
coordinates and valid indices. Invalid requests return an empty result
without partially updated state.

Albion After's `GameServer._alert_infected_pack()` uses this native
broadphase for its established **18-metre** pack-awareness system. Only
alive infected enter the snapshot; current server-authorized chase sources
are frozen before delivering notices. `Zombie.receive_pack_alert()`
continues enforcing valid player targets, safe zones, territory and pursuit
leash. Newly awakened neighbors do not become senders in the same pass.
The stock-Godot/older-Cgame path keeps the original 3×3 GDScript buckets,
so **no game protocol or save format changes** are needed.

Native tests cover negative cells, exact boundaries, deterministic order,
duplicate sources and malformed input. Gameplay tests check native/brute
force parity, one-pass alerts and old-fork fallback. As with all spatial
broadphases, profile actual crowded worlds to confirm the allocation and
CPU overhead justifies the reduction in script loops.

References: spatial partitioning used in Unity-style entity proximity
workflows and Unreal Engine Mass crowd processing; no code copied.

## Bounded nearest-neighbor fanout for dense infected packs

`AIProximityGrid2D.query_nearest_batch(positions, sources, radius, cell_size, max_neighbors)`
selects a maximum of **1–64** closest points for each source (source itself
excluded). Distance ties choose the smaller **original input index**. The
returned indices are sorted by input index, preserving authoritative game
event order irrespective of bucket iteration. Exact radius hits are included.

Capped queries retain at most K candidates per source while scanning the
same 3×3 spatial buckets. The original four-argument
`query_radius_batch()` remains unchanged, with no neighbor limit.

Albion After now alerts at most **12 nearest infected per active source**
within the established **18-metre** awareness radius. This prevents sudden,
unbounded mass wake-ups in dense crowds while retaining server-side
`Zombie.receive_pack_alert()` checks for legitimate players, safe hubs,
combat state, territory and pursuit limits. Sources are frozen before alerts
so freshly recruited NPCs cannot relay alerts during the same pass.

`game/scripts/shared/pack_neighbor_selection.gd` performs equivalent
distance/radius/tie selection for stock Godot and older engine builds,
using the existing 3×3 GDScript buckets. Server-only
`last_pack_query_stats` reports the selected cap and number of successful
notifications. The selection never permits a client to provide arbitrary
target IDs, and does not modify networking or save formats.

### Testing

Native C++ tests verify equal-distance ties, stable ordering, inclusive
radius, dense crowds, bounds and full backward compatibility of the
uncapped API. Albion After server tests compare fallback/native behavior
on an intentionally reverse-ordered 19-member group (12 wake, 6 remain
unalerted). The scoped CI workflow builds the custom Godot engine and
runs headless tests. Benchmark actual frame time on dense encounters before
asserting performance gains.
