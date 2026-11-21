# Albion After: native AI perception bridge

The authoritative zombie simulation in `game/scripts/shared/zombie.gd` now recognizes the optional Cgame native classes `AIVisualSensor2D` and `AIHearingSensor2D`. The gameplay integration lives in `game/scripts/shared/native_infected_senses.gd`; the standalone demonstration and native C++ modules are in `modules/behavior_tree/`.

## What changes

- Existing `infected_sight.gd` controls visual line of sight and obstruction. During hunter tracking, its validated result updates `AIVisualSensor2D` (360-degree field of view to preserve current game logic). Hidden players no longer overwrite a hunter's last confirmed sight position.
- Existing `infected_hearing.gd` and `wind_hearing.gd` continue to decide whether footsteps/gunshots are audible, with wind direction, attenuation, pursuit leash and safe zones. Only **already-accepted** sound stimuli reach the native `AIHearingSensor2D` cache.
- If the survivor escapes chase distance and the NPC has a recent remembered sound but no remembered sight, it investigates that last heard location. Native memory never introduces a new target or bypasses existing server checks.
- Sensors are created lazily per infected NPC, so idle unengaged NPCs do not allocate them. Audio is represented by gameplay events; real `AudioStreamPlayer` playback alone is not a stimulus.
- The GDScript adapter checks `ClassDB.class_exists()` and falls back to its previous behavior under stock Godot, which cannot instantiate these fork-specific classes.

## Multi-source perception history

The engine now has an optional native `AIStimulusHistory2D`, inspired by Unreal AI Perception's per-source stimuli and age. It holds up to 16 events by default, configurable from 1 to 64, with a `source_id`, sense (`SIGHT`, `SOUND`, `DAMAGE`), position, priority strength, and remaining lifetime. An identified source refreshes its record instead of duplicating it; older entries expire or are evicted at capacity.

`native_infected_senses.gd` records only **server-confirmed** sights and sounds from the existing occlusion, wind, safe-zone, sound and leash checks. It never reads hidden target movement into the visual history. Sound ranking within the history considers a signal's intensity and age, and `best_confirmed_stimulus(sense)` returns the highest-scoring current event. If a chased target escapes the pursuit leash and the original ranked sound has expired, the NPC may investigate a separately confirmed still-live sound. **The history never sets combat targets, generates damage, or bypasses a protected player.**

The native class is created lazily together with the existing senses. On stock Godot the new methods return empty dictionaries/lists, and original AI behavior is preserved. For diagnostics, call `zombie.get_ai_debug_snapshot()["perception"]` on the authoritative server to inspect the `stimulus_count`, `best_sight_stimulus`, `best_sound_stimulus`, and up to eight `recent_stimuli`. These records contain last-seen player IDs/positions and **must never be sent to untrusted multiplayer clients**.

```gdscript
var senses := NativeSenses.new() # From res://scripts/shared/native_infected_senses.gd
senses.record_confirmed_sound(listener, accepted_position, approved_hearing_range, server_peer_id)
var best_sound := senses.best_confirmed_stimulus(1)
```

## Bounded spatial stimulus queries and hot-path refresh

The fork's `AIStimulusHistory2D.get_best_in_radius(sense, center, radius)` ranks only
**already server-validated** stimuli within an inclusive, finite 2D radius.
It leaves source lifetimes and memory untouched, returns an empty dictionary
for an invalid sense/center/radius, and preserves the deterministic tie-breaker
of `get_best()`. This is a spatial filter over past observations, **not** a
new line-of-sight or hearing check.

During chase recovery the canonical infected now uses this query for the
secondary remembered sound when the primary ranked hearing memory has expired.
A sound from a valid but distant prior location can no longer redirect a lost
NPC beyond its present pursuit leash. Old Cgame binaries use a bounded
GDScript query over up to 64 recorded stimuli; stock Godot keeps its empty
native-memory fallback. The primary ranked hearing and sight paths retain
their existing behavior, and network replication/target selection are unchanged.

The native history also updates the most-recent identified source in place,
rather than removing and re-appending a `Vector` element on repeated 30 Hz AI
perception ticks. Older-source updates still move to the newest slot so
bounded event eviction semantics remain unchanged. Engine tests cover radius
edges, tie ranking, invalid input, snapshot isolation, age/expiry and hot-path
refresh. `test_native_infected_senses.gd` covers actual game adapter usage.

## Per-actor stimulus queries and precise lost-target investigations

Unreal AI Perception supports looking up **what was sensed about a specific
actor**. Cgame now exposes a bounded, read-only equivalent:
`AIStimulusHistory2D.get_best_for_source(sense, source_id)` and
`get_best_for_source_in_radius(sense, source_id, center, radius)`. Both
return detached snapshots of already accepted stimuli, filtered before
ranking. Unknown/anonymous source IDs, unsupported senses and invalid
spatial inputs return an empty dictionary. Each query scans only the at-most
64 native history records, and doesn't materialize `get_recent()` arrays.
The radius boundary is inclusive and source TTL/eviction is unchanged.

In Albion After, once a zombie's current quarry escapes the pursuit leash,
the server first checks a still-live confirmed sound **from that particular
quarry** and inside the present leash. Only if none exists does it use the
previous primary-ranked sound and secondary sound recovery paths. This
prevents a louder third party from replacing a known quarry's earlier
confirmed investigation point. No current hidden player position, new
sensor signal, client data, or fresh combat target is introduced. Existing
safe-zone, affiliation, LOS and damage rules remain authoritative.

The adapter uses `get_recent(64)` on older Cgame binaries lacking the new
native API and returns an empty result on stock Godot. C++ and GDScript
regressions cover source isolation, inclusive spatial boundaries, lifecycle
expiry, the actual lost-chase transition and fallback compatibility.

## Per-source forgetting after authoritative invalidation

Cgame now exposes `AIStimulusHistory2D.forget_source(source_id, sense = -1)`.
It selectively removes a known stimulus source from one or all senses and
returns the number of removed entries. Negative and unknown IDs, unsupported
sense values, and repeated calls remove nothing. Existing observations from
other sources retain their original age, insertion order, and ranking.
Anonymous stimuli (source ID -1) cannot be selectively invalidated.

Albion After's authoritative infected chase/attack state uses this method
when a tracked survivor disconnects, dies, or becomes safe. This removes
**only source-tagged history** after the existing game rules have already
invalidated the target. The separate legacy primary sight/hearing caches are
not source-tagged and continue to expire normally; they are not used to
generate any new target here. On stock Godot and older Cgame binaries the
adapter leaves memory unchanged rather than clearing other survivors' data.
The server remains the sole authority for detection, combat and safe zones.

Engine tests cover selective sense removal, retained time-to-live, ordering,
invalid inputs and idempotence. Game tests exercise the actual chase release
for safe-zone and disconnected survivors. No network payloads are changed.

## Behavior trees

`BehaviorTreeReactiveSelector` and `BehaviorTreeReactiveSequence` extend the existing `BehaviorTreeComposite` **Resource** classes in the current `develop` branch. They reevaluate priority and guards per runner tick and cancel the execution memory of an interrupted branch. The existing `BehaviorTreeRunner`, `BehaviorTreeBlackboardCheck`, `BehaviorTreeBlackboardSet`, `BehaviorTreeWait` remain intact. The canonical server simulation keeps its existing state machine because its combat, networking and AI authority requirements are richer than the example tree.

The executable sandbox `modules/behavior_tree/demo_reactive_ai/` demonstrates the resource tree API and how it combines with native senses and 2D `AStarGrid2D`.

## Server-only AI diagnostics

`native_infected_senses.gd` exposes an on-demand `get_debug_snapshot()` with the availability and expiry of native sight/sound memories and their last confirmed positions. The canonical zombie class offers `get_ai_debug_snapshot()` with its current state, target ID and nested perception snapshot. The engine's `BehaviorTreeRunner.get_debug_snapshot()` returns detached copies of its Blackboard and execution-memory state for tools. These values are intended for local debugging and server operators and **must not be broadcast to ordinary multiplayer clients**, since they can reveal a hidden player's position or identity.

The engine also provides `BehaviorTreeBlackboardCompare`: a Resource guard supporting equality, numeric ordering, existence checks and optional comparison to a second Blackboard key. The accompanying playable AI sandbox uses it for the native low-health retreat threshold without modifying the main game's authoritative infected targeting logic.

## Server-only AI decision replay

After enabling optional native tracing for **one** authoritative infected NPC, Albion After now retains up to **eight** recent simulation ticks for that NPC only. `Zombie.get_ai_trace_history_frames(changes_only)` returns detached snapshots for server debugging, where changes are based on task paths and statuses rather than noisy CPU duration fluctuations. `Zombie.get_ai_slowest_trace_nodes(limit)` reports the most expensive observed task stages, with estimated exclusive CPU time as `self_usec` and inclusive time as `duration_usec`.

```gdscript
if zombie.enable_ai_trace(true):
    # After one or more server zombie.think(...) calls:
    var changes: Array = zombie.get_ai_trace_history_frames(true)
    var slowest: Array = zombie.get_ai_slowest_trace_nodes(4)
    # Disable the optional recorder when diagnosis is finished.
    zombie.enable_ai_trace(false)
```

A `trace_history` (changed-only) Array and a bounded `slowest_ai_phases` Array are also available in `Zombie.get_ai_debug_snapshot()`. **Never broadcast those snapshots or player IDs to untrusted clients.** Tracing is not enabled by the normal game, and the existing state machine's decisions, threat, safe zones and authoritative combat remain unchanged.

## Visual AI debugger and authoritative infected state views

The native `BehaviorTreeRunner.get_tree_snapshot()` enumerates all static child Resource occurrences (up to 256 nodes), merges visited/unvisited status from its per-node execution trace, and returns a detached hierarchy for visual displays. Both Godot projects now include the enabled `Cgame AI` editor dock under `res://addons/cgame_bt_debugger/`. It inspects a selected BehaviorTreeRunner in the **edited scene**; live game-side task execution is shown in the playable AI sandbox's **T**-toggle Tree panel instead of claiming remote editor-debugger attachment.

Because Albion After zombies use an authoritative **GDScript state machine**, their new `Zombie.get_ai_state_visual_snapshot()` explicitly labels the state-machine root and its six actual states, highlights exactly the current one, and adds a target-selection phase only when native server tracing recorded it. It shares the inspector's `nodes` format and is available through `get_ai_debug_snapshot()["visual_tree"]`. These are on-demand, server-only tools and are **not** included in network snapshots, messages or public gameplay UI. Target IDs and last-known positions remain private to the server.

## Optional per-node and server decision tracing

The engine's `AIBehaviorTrace` can now record a bounded timeline for individual BehaviorTree nodes: `path`, `task_class`, `depth`, `status`, and `duration_usec` for each executed task. Use `BehaviorTreeRunner.trace_enabled = true` on a single agent, then inspect `get_trace_snapshot()["steps"]`. It preserves a maximum of 128 entries per tick by default and reports overflow rather than retaining unlimited data.

The canonical Albion After zombie AI is currently an authoritative GDScript state machine, not a BehaviorTree. It now uses the **same native trace recorder**, optionally and only for real target-selection passes:

```gdscript
var available := zombie.enable_ai_trace(true) # False on stock Godot.
# After the server runs zombie.think(...) with an eligible target scan:
var diagnostics: Dictionary = zombie.get_ai_trace_snapshot()
# A confirmed scan appears as task_class="ZombieTargetSelection".
zombie.enable_ai_trace(false)
```

The snapshot also appears under `zombie.get_ai_debug_snapshot()["trace"]`. This is server-only diagnostic data: trace entries can expose decisions involving other players. Do not replicate it to ordinary clients. Profiling/tracing are disabled by default on game NPCs and do not affect target acquisition, authoritative checks, combat timers or random-number generation. The playable native BehaviorTree demo provides a **T** toggle and HUD inspector for per-node traces.

## Opt-in AI CPU profiling

The native `AIExecutionProfiler` measures named AI phases with Godot's monotonic microsecond clock. It tracks the last, min, max, mean and total microseconds, sample counts and overruns of a configurable budget. It is disabled by default, stores at most 32 phase names, and provides an on-demand `get_snapshot()` for investigations rather than an always-on telemetry stream.

For **Albion After**, server-authoritative `Zombie` objects support:
```gdscript
var enabled: bool = zombie.enable_ai_profiling(true) # false on stock Godot
# After zombie.think() runs at least once and target selection is due:
var metrics: Dictionary = zombie.get_ai_profile_snapshot()
var categories: Dictionary = metrics.get("categories", {})
var selection: Dictionary = categories.get("target_selection", {})
print("Target selection (microseconds): ", selection.get("mean_usec", 0.0))
zombie.enable_ai_profiling(false)
zombie.reset_ai_profile()
```

Only the selected NPC allocates a profiler. A phase named `target_selection` measures the server's actual target-selection routine; no combat rules or network payloads are changed. Per-agent timings are also included in the existing server-only `Zombie.get_ai_debug_snapshot()` response, **never automatically sent to ordinary players**.

The engine's `BehaviorTreeRunner` has `profiling_enabled`, `get_profile_snapshot()` and `reset_profile()` for the complete root task execution, including child evaluation. Finished cached ticks do not count as fresh samples. Use the engine profiler or external system tools for whole-frame or C++ call-stack analysis; this is lightweight per-agent instrumentation, not a replacement.

## Native time limits and howl cooldowns

The behavior-tree module now supplies `BehaviorTreeTimeout` for per-runner child-task deadlines and `BehaviorTreeCooldown` for success-triggered branch locks. Unlike a wall-clock timer, both consume the simulation delta delivered to a running branch; interruption or `BehaviorTreeRunner.reset()` clears their branch memory.

The canonical multiplayer AI uses a separate native `AIActionCooldowns` Resource-like RefCounted ledger on the authoritative `Zombie` for **pack howl events**. A howler that notices several different survivors quickly can alert the pack once and must wait **6 seconds of server simulation time** before a new howl. This class allocates lazily only after a confirmed howl. It never affects ordinary melee damage, attack-rate timers, protected-zone checks or other infected types. The server-only `Zombie.get_ai_debug_snapshot()` reports `pack_howl_cooldown_seconds` for diagnostics.

On a stock Godot build, there is no `AIActionCooldowns` class and howl processing keeps its previous one-per-survivor behavior. The playable native AI demo uses the new `BehaviorTreeTimeout` to exit an overlong sound investigation and a native action cooldown to gate repeated player shouts. See `modules/behavior_tree/demo_reactive_ai/README.md`.

## Large-group AI scheduling

The engine now provides `AIUpdateScheduler` for deterministic per-agent update slots. The canonical `GameServer` uses it to spread nonurgent target selection only when at least 128 infected are present, with combat and first-selection bypasses and a stock-Godot fallback. See [AI Update Scheduling](AI_UPDATE_SCHEDULING.md) for the precise behavior, server diagnostics and tests.

## Validation

New automated `game/tests/test_native_infected_senses.gd` is listed in the canonical `game/tests/run_all.gd`. It verifies fallback behavior, temporary sense memory, accepted sound events and safe-zone immunity. Native C++ tests cover perception rules and reactive preemption; sandbox integration scripts cover actual LOS and obstacle A* navigation.

```sh
scons platform=linuxbsd target=editor tests=yes -j"$(nproc)"
./bin/godot.linuxbsd.editor.x86_64 --headless --test
./bin/godot.linuxbsd.editor.x86_64 --headless --path game --script res://tests/run_all.gd
./bin/godot.linuxbsd.editor.x86_64 --headless --path modules/behavior_tree/demo_reactive_ai --script res://tests/smoke_demo.gd
./bin/godot.linuxbsd.editor.x86_64 --headless --path modules/behavior_tree/demo_reactive_ai --script res://tests/smoke_navigation_hearing.gd
```

These commands require a **compiled fork binary** to exercise the new native classes. Without one, the game suite can exercise the fallback only.

## Scope

This is opt-in memory for validated AI stimuli, not a replacement for existing wind acoustics, environment-query flanking, state-machine combat, physics navigation, network replication or faction targeting. Avoid promoting native observations to server target selection without preserving all current safety and combat constraints.

## Bounded ranked investigation follow-ups

Unreal's AI Perception supports timed per-sense stimuli and multiple perceived
sources. This project adds only the modest **already confirmed** ranking
operation `AIStimulusHistory2D.get_ranked(sense,limit)`, with deterministic
strength × remaining TTL ordering, explicit maximum 64, and detached results.

The authoritative Zombie may investigate one second location after reaching
a confirmed first sound. The location must still have a live history event,
be distinct by 2 m, and lie inside its current pursuit leash. The total
search budget remains unchanged (4 seconds for ordinary infected).
No search query acquires a target, bypasses original hearing validation,
creates a visual observation, or changes network snapshots. Stock Godot and
older Cgame retain their prior single-position behavior.

Inspect `NativeInfectedSenses.get_debug_snapshot()["ranked_sound_stimuli"]`
only on a trusted server: source IDs/last perceived positions are sensitive
AI information and must never be broadcast to untrusted players.

A follow-up memory point is rechecked against the current server safe-zone and water rules before selection; an old sound is never permission to enter the protected hub.
