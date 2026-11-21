# Reactive NPC AI — Cgame develop integration

A self-contained 2D sandbox for this fork's **resource-backed** behavior-tree runtime plus its native sight and hearing sensors. This project is separate from the canonical *Albion After* game in `game/`; the engine functionality is also wired into that game's server infected AI through `native_infected_senses.gd`.

## Interactive replay and bottleneck inspection

In the playable AI sandbox, press **T** to show the live task tree. The **Prev / Next / Live** controls step through up to **16 retained native AI ticks**, and **Changed decisions only** skips frames with identical executed task paths and statuses even when CPU timings jitter. The lower readout names the latest highest-cost node, displaying **self (exclusive approximation)** and **total (inclusive)** microseconds. Replay only changes the inspector's displayed past trace: gameplay AI, world state and physics are not rewound. Press **Live** to follow the newest tick again.

The native history is independent per `BehaviorTreeRunner`, disabled by default on production game agents, and bounded both in number of ticks (32 maximum) and tasks per tick (256 maximum).

## Editor dock and playable visual inspector

Open this project in the custom Cgame Godot editor. The enabled `Cgame BehaviorTree Inspector` addon opens a right-hand **Cgame AI** dock that shows all child Resource tasks of an edited scene's `BehaviorTreeRunner`, even branches not executed. Select the runner node and press **Refresh**; this editor-side inspector observes the edited scene, not the remote running game.

Run the sandbox and press **T** to show or hide a separate live hierarchical panel, updated on every 0.2-second AI tick. It shows `SUCCESS` (green), `FAILURE` (red), `RUNNING` (amber) and `NOT RUN` (gray) with nested paths and elapsed CPU microseconds. The native `get_tree_snapshot()` returns at most 256 Resource occurrences and works independently of the separate performance profiler toggled with **P**.

## Run

```sh
./bin/godot.linuxbsd.editor.x86_64 --path modules/behavior_tree/demo_reactive_ai
```

**Per-node debugger:** tracing is enabled in the demo by default. Press **T** to toggle its bounded runtime task history independently of **P** profiling. The HUD reports how many task nodes were entered on the latest AI tick and the active nested node path; the full detached timeline is available through `brain.get_trace_snapshot()`. The native engine records the precise Resource task type, status and inclusive CPU microseconds for each node. The automatic smoke test checks the root and nested chase branch.

Move the blue survivor with **arrow keys**, press **F** to shout, **Space** near the infected to attack, **P** to enable/disable and reset AI CPU profiling, **R** to restart. The demo enables profiling initially so the bottom HUD line displays average/max behavior-tree decision time in microseconds. All other game NPCs default to unprofiled operation. Movement emits quieter footsteps. The wall blocks sight and attenuates sound. The NPC follows paths around the wall, remembers the player's last visible position, and investigates the last heard sound.

Navigation replans are immediately triggered when switching actions; while chasing a moving target, A* refreshes on the NPC's designated one-in-four AI tick. HUD shows how many real path queries ran, their mean CPU time and the ticks until the next slot. The canonical game uses the same scheduler for large infected groups; see `game/docs/AI_UPDATE_SCHEDULING.md`.

The native `BehaviorTreeTimeout` enforces a 0.8-second deadline on a 2-second audio investigation task, allowing patrol fallback if that task cannot finish. Pressing **F** uses an `AIActionCooldowns` instance to prevent shout-spam; the HUD displays its remaining time. In the canonical multiplayer game, the same native action gate prevents a howler from creating repeated pack alerts when it acquires different survivors in rapid succession.

The game uses:
- `BehaviorTreeRunner` (Node) with `BehaviorTreeReactiveSelector` and `BehaviorTreeReactiveSequence` (Resource tasks);
- `BehaviorTreeBlackboardCheck`, `BehaviorTreeBlackboardCompare`, `BehaviorTreeBlackboardSet`, and `BehaviorTreeWait` (time-based waits);
- `AIVisualSensor2D`, `AIHearingSensor2D` (native reusable sensors);
- `AIStimulusHistory2D` (bounded expiry-aware, source-tagged sight and sound memory, shown in HUD);
- `AIUpdateScheduler` (native deterministic NPC update slots) and `AIExecutionProfiler` (native timings for actual A* route recalculations);
- Godot `AStarGrid2D` with an inflated four-way grid for obstacle navigation;
- a `StaticBody2D` and `PhysicsRayQueryParameters2D` for line-of-sight.

**AI priorities**: retreat (numeric HP <= Blackboard threshold) → chase (visible) → investigate last seen → investigate sound → patrol. The retreat guard uses a native `BehaviorTreeBlackboardCompare` resource to compare the live `health` key against `retreat_at_or_below`, rather than an external GDScript Boolean. The reactive selector rechecks higher priorities every AI tick. On any terminal result the demo resets the `BehaviorTreeRunner` before its next tick, because this API caches terminal status. Blackboard writes are applied by native `BehaviorTreeBlackboardSet` resources.

## Automatic tests

Build the fork with unit tests, then execute:

```sh
scons platform=linuxbsd target=editor tests=yes -j"$(nproc)"
./bin/godot.linuxbsd.editor.x86_64 --headless --test
./bin/godot.linuxbsd.editor.x86_64 --headless --path modules/behavior_tree/demo_reactive_ai --script res://tests/smoke_demo.gd
./bin/godot.linuxbsd.editor.x86_64 --headless --path modules/behavior_tree/demo_reactive_ai --script res://tests/smoke_navigation_hearing.gd
./bin/godot.linuxbsd.editor.x86_64 --headless --path game --script res://tests/run_all.gd
```

Native doctest cases: `modules/behavior_tree/tests/test_reactive_behavior_tree.h`, `test_ai_visual_sensor_2d.h`, `test_ai_hearing_sensor_2d.h`.

The Cgame native AI classes are **not** part of stock Godot. Running the standalone sandbox requires the fork's compiled binary. The canonical game's `native_infected_senses.gd` instead gracefully degrades to the existing GDScript hearing/sight logic when the custom native classes are unavailable.

## Limits

This demo has a static grid, one NPC, and one player. It is not a 3D navigation mesh, group steering, replicated server combat, or a substitute for the canonical game. For the main game, only already-authorized hearing and visual events enter the new native sensor memory; its existing server combat, safe-zone, wind, line-of-sight, scent and threat rules remain authoritative.
