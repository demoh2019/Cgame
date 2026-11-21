# Albion After: native AI perception bridge

The authoritative zombie simulation in `game/scripts/shared/zombie.gd` now recognizes the optional Cgame native classes `AIVisualSensor2D` and `AIHearingSensor2D`. The gameplay integration lives in `game/scripts/shared/native_infected_senses.gd`; the standalone demonstration and native C++ modules are in `modules/behavior_tree/`.

## What changes

- Existing `infected_sight.gd` controls visual line of sight and obstruction. During hunter tracking, its validated result updates `AIVisualSensor2D` (360-degree field of view to preserve current game logic). Hidden players no longer overwrite a hunter's last confirmed sight position.
- Existing `infected_hearing.gd` and `wind_hearing.gd` continue to decide whether footsteps/gunshots are audible, with wind direction, attenuation, pursuit leash and safe zones. Only **already-accepted** sound stimuli reach the native `AIHearingSensor2D` cache.
- If the survivor escapes chase distance and the NPC has a recent remembered sound but no remembered sight, it investigates that last heard location. Native memory never introduces a new target or bypasses existing server checks.
- Sensors are created lazily per infected NPC, so idle unengaged NPCs do not allocate them. Audio is represented by gameplay events; real `AudioStreamPlayer` playback alone is not a stimulus.
- The GDScript adapter checks `ClassDB.class_exists()` and falls back to its previous behavior under stock Godot, which cannot instantiate these fork-specific classes.

## Behavior trees

`BehaviorTreeReactiveSelector` and `BehaviorTreeReactiveSequence` extend the existing `BehaviorTreeComposite` **Resource** classes in the current `develop` branch. They reevaluate priority and guards per runner tick and cancel the execution memory of an interrupted branch. The existing `BehaviorTreeRunner`, `BehaviorTreeBlackboardCheck`, `BehaviorTreeBlackboardSet`, `BehaviorTreeWait` remain intact. The canonical server simulation keeps its existing state machine because its combat, networking and AI authority requirements are richer than the example tree.

The executable sandbox `modules/behavior_tree/demo_reactive_ai/` demonstrates the resource tree API and how it combines with native senses and 2D `AStarGrid2D`.

## Server-only AI diagnostics

`native_infected_senses.gd` exposes an on-demand `get_debug_snapshot()` with the availability and expiry of native sight/sound memories and their last confirmed positions. The canonical zombie class offers `get_ai_debug_snapshot()` with its current state, target ID and nested perception snapshot. The engine's `BehaviorTreeRunner.get_debug_snapshot()` returns detached copies of its Blackboard and execution-memory state for tools. These values are intended for local debugging and server operators and **must not be broadcast to ordinary multiplayer clients**, since they can reveal a hidden player's position or identity.

The engine also provides `BehaviorTreeBlackboardCompare`: a Resource guard supporting equality, numeric ordering, existence checks and optional comparison to a second Blackboard key. The accompanying playable AI sandbox uses it for the native low-health retreat threshold without modifying the main game's authoritative infected targeting logic.

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
